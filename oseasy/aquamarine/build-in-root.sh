#!/bin/bash
# build-in-root.sh OUTDIR: build Arch's aquamarine package, at the version this
# root has installed, with the patches next to this script. Runs as root inside
# a throwaway copy of the Omarchy root (27-build-aquamarine.sh chroots into an
# overlay of the image), so it can sync and install the build tools freely; the
# build itself runs as nobody.
#
# Why: on efidrm, aquamarine retries its EGL renderer on every commit and logs
# four errors per frame (0001-*.patch). The package keeps Arch's name and
# version with pkgrel N.1, so the next upstream release replaces it.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
out=${1:?usage: build-in-root.sh OUTDIR}
ver=$(pacman -Q aquamarine | cut -d' ' -f2)
work=$(mktemp -d /var/tmp/aquamarine.XXXX)

pacman -Sy --needed --noconfirm base-devel cmake hyprwayland-scanner >/dev/null
curl -fsSL "https://gitlab.archlinux.org/archlinux/packaging/packages/aquamarine/-/raw/$ver/PKGBUILD" -o "$work/PKGBUILD"
cp "$here"/0*.patch "$work/"

# Add the patches to source=() and apply them in prepare().
cd "$work"
patches=$(ls 0*.patch | tr '\n' ' ')
sed -i "s/^pkgrel=\(.*\)/pkgrel=\1.1/" PKGBUILD
sed -i "s/^source=(\(.*\))$/source=(\1 $patches)/" PKGBUILD
# shellcheck disable=SC2086  # one SKIP per patch
sed -i "s/^sha256sums=(\(.*\))$/sha256sums=(\1 $(printf 'SKIP %.0s' $patches))/" PKGBUILD
cat >> PKGBUILD <<'EOF'

prepare() {
	cd "$_archive"
	for p in "$srcdir"/0*.patch; do
		patch -Np1 -i "$p"
	done
}
EOF

chown -R nobody: "$work"
runuser -u nobody -- env HOME="$work" makepkg -f --noconfirm --skippgpcheck >/dev/null
mkdir -p "$out"
cp "$work"/aquamarine-*.pkg.tar.* "$out/"
rm -rf "$work"
ls "$out"/aquamarine-*.pkg.tar.*
