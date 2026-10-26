#!/usr/bin/env bash
# Build the 6.1 boot entries (UKIs) from Omarchy's own UKI and initramfs plus the
# Debian kernel, and install them with a Limine menu into the image's ESP.
set -euo pipefail
. "$(dirname "$0")/config.sh"
need mcopy mdir mmd cpio depmod python3
cd "$WORK"; . ./image.env
K=$WORK/k61 B=$WORK/boot L=$OHMARCHY_ROOT/oseasy/lib
E="omarchy.raw@@$ESP_OFFSET"
rm -rf "$B"; mkdir -p "$B"

# base: Omarchy's UKI (stub + its mkinitcpio initramfs, which is kernel-agnostic userspace)
BASE=EFI/Linux/omarchy_linux.efi
mdir -i "$E" "::/$BASE" >/dev/null 2>&1 || BASE=$(mdir -b -i "$E" ::/EFI/Linux | grep -i '\.efi$' | head -1 | sed 's#^::/##')
mcopy -o -i "$E" "::/$BASE" "$B/base.efi"
python3 "$L/uki.py" get "$B/base.efi" .initrd "$B/omarchy-initrd.img"

# 6.1 modules the initramfs needs (dependencies resolved from modules.dep).
# crc32c_generic is listed by hand: libcrc32c (needed by btrfs) only names it as a
# softdep, which modules.dep does not carry, and without it btrfs fails to load.
python3 "$L/modsubset.py" "$K/modroot" "$KVER" "$B/sub" \
    virtio_pci virtio_blk virtio_net virtio_rng virtio_console btrfs crc32c_generic vfat nls_ascii nls_cp437 \
    nls_iso8859_1 nls_utf8 xhci_pci usbhid hid_generic fuse virtiofs vmwgfx omarchy_efidrm
depmod -b "$B/sub" "$KVER" 2>/dev/null || depmod -b "$B/sub/usr" "$KVER"
( cd "$B/sub" && find . -mindepth 1 | LC_ALL=C sort | cpio --quiet -o -H newc -R 0:0 ) > "$B/modules.cpio"

# overlay: hooks, scripts, modprobe policy and the mkinitcpio /config
mkdir -p "$B/ov"; cp -a "$OHMARCHY_ROOT/oseasy/initramfs/." "$B/ov/"
# the installed system's Oseasy setup (oseasy/root), copied into the root by omarchy-late
mkdir -p "$B/ov/ohmarchy-root"; cp -a "$OHMARCHY_ROOT/oseasy/root/." "$B/ov/ohmarchy-root/"
mv "$B/ov/config-6.1" "$B/ov/config"
( cd "$B/ov" && find . -mindepth 1 | LC_ALL=C sort | cpio --quiet -o -H newc -R 0:0 ) > "$B/overlay.cpio"

CMD="root=UUID=$ROOT_UUID $KCMD_BASE"
mk() { python3 "$L/uki.py" build "$B/base.efi" "$B/$1" --linux "$K/Image" --uname "$KVER" \
        --initrd "$B/omarchy-initrd.img" --initrd "$B/modules.cpio" --initrd "$B/overlay.cpio" --cmdline "$CMD $2"; }
mk ohmarchy-6.1.efi        ""
mk ohmarchy-6.1-hold.efi   "omarchy_hold=1"
mk ohmarchy-6.1-efidrm.efi "omarchy_gpu=efidrm"
mk ohmarchy-6.1-svga.efi   "omarchy_gpu=svga"

# install: UKIs, module tarball, Limine menu; Limine becomes the fallback loader
for f in "$B"/ohmarchy-6.1*.efi; do mcopy -o -i "$E" "$f" ::/EFI/Linux/; done
mmd -i "$E" ::/ohmarchy 2>/dev/null || true
mcopy -o -i "$E" "$K/modules-$KVER.tar.gz" ::/ohmarchy/
mcopy -n -i "$E" ::/limine.conf "$B/limine.conf.omarchy" 2>/dev/null && mcopy -o -i "$E" "$B/limine.conf.omarchy" ::/ohmarchy/limine.conf.omarchy || true
mcopy -o -i "$E" "$OHMARCHY_ROOT/oseasy/limine.conf.in" ::/limine.conf

# Patched 7.2 kernel (25-build-kernel-7.2.sh), when built: the same initramfs
# layers with its own module subset, plus two earlycon entries that show where a
# kernel stops (earlycon starts after __cpu_setup, so a hang there prints nothing).
K72=$WORK/k72
if [ -s "$K72/kver" ]; then
    KV72=$(cat "$K72/kver")
    python3 "$L/modsubset.py" "$K72/modroot" "$KV72" "$B/sub72" \
        virtio_pci virtio_blk virtio_net virtio_rng virtio_console btrfs vfat nls_ascii nls_cp437 \
        nls_iso8859_1 nls_utf8 xhci_pci usbhid hid_generic fuse virtiofs
    depmod -b "$B/sub72" "$KV72" 2>/dev/null || depmod -b "$B/sub72/usr" "$KV72"
    ( cd "$B/sub72" && find . -mindepth 1 | LC_ALL=C sort | cpio --quiet -o -H newc -R 0:0 ) > "$B/modules72.cpio"
    EARLYCON="earlycon=efifb keep_bootcon ignore_loglevel"
    mk72() { python3 "$L/uki.py" build "$B/base.efi" "$B/$1" --linux "$K72/Image" --uname "$KV72" \
            --initrd "$B/omarchy-initrd.img" --initrd "$B/modules72.cpio" --initrd "$B/overlay.cpio" --cmdline "$CMD $2"; }
    mk72 ohmarchy-7.2.efi          "$K72_CMDLINE_EXTRA"
    mk72 ohmarchy-7.2-earlycon.efi "$K72_CMDLINE_EXTRA $EARLYCON"
    for f in "$B"/ohmarchy-7.2*.efi; do mcopy -o -i "$E" "$f" ::/EFI/Linux/; done
    mdel -i "$E" ::/EFI/Linux/ohmarchy-stock-earlycon.efi 2>/dev/null || true
    # Modules for the first boot (the root only has the stock kernel's), and the
    # kernel as a package: ohmarchy-oseasy-setup installs it before Omarchy's
    # provisioning rebuilds limine.conf (kernel/pkg/PKGBUILD).
    mcopy -o -i "$E" "$K72/modules-$KV72.tar.gz" ::/ohmarchy/
    for f in "$K72"/linux-ohmarchy-oseasy-*.pkg.tar.*; do
        [ -f "$f" ] && mcopy -o -i "$E" "$f" ::/ohmarchy/
    done
    # The 7.2 entry (6th) boots by default: it is the one that reaches the desktop.
    sed 's/^default_entry: .*/default_entry: 6/' "$OHMARCHY_ROOT/oseasy/limine.conf.in" |
        cat - "$OHMARCHY_ROOT/oseasy/limine-7.2.conf.in" > "$B/limine.conf"
    mcopy -o -i "$E" "$B/limine.conf" ::/limine.conf
fi

# aquamarine without the per-frame renderer retry on efidrm (27-build-aquamarine.sh),
# when built; ohmarchy-oseasy-setup installs it over the matching version.
for f in "$WORK"/aquamarine/aquamarine-*.pkg.tar.*; do
    [ -f "$f" ] && mcopy -o -i "$E" "$f" ::/ohmarchy/
done

# The extras (28-build-extras.sh), when built: ohmarchy-glfinish.so and the
# Pinyin packages (with their signatures), installed by ohmarchy-oseasy-setup.
if [ -f "$WORK/extras/ohmarchy-glfinish.so" ]; then
    mmd -i "$E" ::/ohmarchy/extras ::/ohmarchy/extras/pkgs 2>/dev/null || true
    mcopy -o -i "$E" "$WORK/extras/ohmarchy-glfinish.so" ::/ohmarchy/extras/
    for f in "$WORK"/extras/pkgs/*.pkg.tar.*; do
        [ -f "$f" ] && mcopy -o -i "$E" "$f" ::/ohmarchy/extras/pkgs/
    done
fi

mcopy -o -i "$E" ::/EFI/limine/limine_aa64.efi "$B/limine_aa64.efi"
mcopy -o -i "$E" "$B/limine_aa64.efi" ::/EFI/BOOT/BOOTAA64.EFI
mdir -i "$E" ::/EFI/Linux | grep -i efi
mdir -i "$E" ::/ | tail -2
