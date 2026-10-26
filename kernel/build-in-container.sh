#!/usr/bin/env bash
# Build the patched 7.2 kernel inside a Debian container (oseasy/25-build-kernel-7.2.sh).
# /in holds the inputs, /out receives Image, kver, config and the module tarball.
# The tree is built in the container's own filesystem: macOS bind mounts are
# case-insensitive, and netfilter has modules that differ only in case.
set -euo pipefail
: "${K72_VER:?}" "${K72_SERIES:?}" "${K72_LOCALVERSION:?}"

cross=() make_env=()
if [ "$(uname -m)" != aarch64 ]; then
    cross=(crossbuild-essential-arm64)
    make_env=(ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu-)
fi
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends build-essential bc bison flex libssl-dev libelf-dev \
    dwarves python3 cpio kmod xz-utils patch ca-certificates "${cross[@]}" >/dev/null

mkdir -p /build && cd /build
tar -xJf "/in/linux-$K72_SERIES.tar.xz"
cd "linux-$K72_SERIES"
xz -dc "/in/patch-$K72_VER.xz" | patch -p1 -s
for p in /in/alarm/0*.patch; do patch -p1 -s < "$p"; done
for p in /in/01*.patch; do patch -p1 -s < "$p"; done       # kernel/: Oseasy fixes
for p in /in/9*.patch; do [ -e "$p" ] && patch -p1 -s < "$p"; done  # local debug patches, if any

cp /in/alarm/config .config
echo "$K72_LOCALVERSION" > localversion.10-ohmarchy
scripts/kconfig/merge_config.sh -m .config /in/config-7.2.fragment >/dev/null
make "${make_env[@]}" olddefconfig >/dev/null
for opt in CONFIG_ARM64_RAZ_NEW_ID_REGS=y CONFIG_DRM_EFIDRM=y '# CONFIG_FB_EFI is not set'; do
    grep -qx "$opt" .config || { echo "config did not take: $opt" >&2; exit 1; }
done

make "${make_env[@]}" -j"$(nproc)" Image modules
KVER=$(make "${make_env[@]}" -s kernelrelease)
make "${make_env[@]}" -s modules_install INSTALL_MOD_PATH=/build/modroot/usr INSTALL_MOD_STRIP=1
rm -f "/build/modroot/usr/lib/modules/$KVER/build" "/build/modroot/usr/lib/modules/$KVER/source"

cp arch/arm64/boot/Image /out/Image
cp .config /out/config
echo "$KVER" > /out/kver
tar -C /build/modroot -czf "/out/modules-$KVER.tar.gz" "usr/lib/modules/$KVER"
ls -la /out
