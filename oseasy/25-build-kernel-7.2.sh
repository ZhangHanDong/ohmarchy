#!/usr/bin/env bash
# Build the patched 7.2 kernel: Arch Linux ARM's linux-aarch64 (same source,
# patches and config as the kernel in the Omarchy image) plus
# kernel/0100-*.patch and kernel/config-7.2.fragment. Output, laid out like k61:
#   $WORK/k72/Image                        kernel (EFI stub)
#   $WORK/k72/kver                         its uname -r
#   $WORK/k72/modroot/usr/lib/modules/KVER modules, for 40-build-boot.sh
#   $WORK/k72/modules-KVER.tar.gz          the same tree, shipped on the ESP
# The build runs in a container; on an x86 host it cross-compiles. About an hour
# on 8 cores; the container needs ~25 GB.
set -euo pipefail
. "$(dirname "$0")/config.sh"
need curl md5sum tar "$DOCKER"
D=$WORK/dl/k72 K=$WORK/k72 KD=$OHMARCHY_ROOT/kernel
mkdir -p "$D/alarm"; cd "$D"

fetch() {
    local url=$1 f=${2:-${1##*/}}
    [ -s "$f" ] && return 0
    echo "fetch $url"
    curl -fL --retry 3 -o "$f.part" "$url"
    mv "$f.part" "$f"
}

# Arch Linux ARM's recipe at the pinned commit; its md5sums verify every input.
ALARM=https://raw.githubusercontent.com/archlinuxarm/PKGBUILDs/$ALARM_PKGBUILDS_COMMIT/core/linux-aarch64
fetch "$ALARM/PKGBUILD" alarm/PKGBUILD
# PKGBUILD is bash: a subshell sourcing it yields the expanded source/md5sums arrays.
SUMS=()   # no mapfile: macOS ships bash 3.2
while IFS= read -r line; do SUMS+=("$line"); done < <(cd alarm && bash -c '. ./PKGBUILD; [ "$pkgver" = "$1" ] || exit 0
    for i in "${!source[@]}"; do echo "${md5sums[$i]}  ${source[$i]}"; done' _ "$K72_VER")
(( ${#SUMS[@]} )) || die "ALARM PKGBUILD at $ALARM_PKGBUILDS_COMMIT is not $K72_VER"
for line in "${SUMS[@]}"; do
    sum=${line%%  *} src=${line#*  }
    case $src in
        https://*.tar.xz|https://*/patch-*.xz) fetch "$src"; f=${src##*/} ;;
        0*.patch|config) fetch "$ALARM/$src" "alarm/$src"; f=alarm/$src ;;
        *) continue ;;   # Chromebook signing files and the preset: not needed for Image + modules
    esac
    echo "$sum  $f" | md5sum -c --quiet || die "md5 mismatch: $f"
done

rm -f "$D"/01*.patch; cp "$KD"/01*.patch "$KD/config-7.2.fragment" "$D/"
rm -rf "$K"; mkdir -p "$K/modroot"
"$DOCKER" run --rm \
    -e K72_VER="$K72_VER" -e K72_SERIES="$K72_SERIES" -e K72_LOCALVERSION="$K72_LOCALVERSION" \
    -v "$D:/in:ro" -v "$K:/out" -v "$KD/build-in-container.sh:/build.sh:ro" \
    "$KERNEL_BUILD_IMAGE" bash /build.sh

KVER=$(cat "$K/kver")
tar -xzf "$K/modules-$KVER.tar.gz" -C "$K/modroot"
ls -la "$K/Image" "$K/modules-$KVER.tar.gz"
echo "kernel $KVER"
