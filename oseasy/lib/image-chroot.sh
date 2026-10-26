# shellcheck shell=bash
# image_chroot NAME SRC OUT CMD... (sourced by oseasy/2x-build-*.sh): run CMD as
# root inside a throwaway copy of the Omarchy image's root, so what it builds
# matches the libraries the image runs with. The root is the image's btrfs @
# subvolume, read-only under an overlay in $WORK/NAME-build (removed afterwards);
# SRC is bound at /ohmarchy and OUT at /ohmarchy-out. Needs root, btrfs and
# overlayfs, and an aarch64 host (or binfmt qemu-aarch64 for the chroot).
image_chroot() {
    local name=$1 src=$2 out=$3; shift 3
    local T=$WORK/$name-build loop m
    mkdir -p "$T"/lower "$T"/upper "$T"/work "$T"/root "$out"
    loop=$(losetup -f --show -r -o "$ROOT_OFFSET" "$WORK/omarchy.raw")
    # shellcheck disable=SC2064  # expand now: the trap outlives these locals
    trap "image_chroot_cleanup '$T' '$loop'" EXIT

    mount -t btrfs -o ro,subvol=@ "$loop" "$T/lower"
    mount -t overlay overlay -o "lowerdir=$T/lower,upperdir=$T/upper,workdir=$T/work" "$T/root"
    for m in proc sys dev; do mount --rbind "/$m" "$T/root/$m"; done
    mkdir -p "$T/root/ohmarchy" "$T/root/ohmarchy-out"
    mount --bind "$src" "$T/root/ohmarchy"
    mount --bind "$out" "$T/root/ohmarchy-out"
    rm -f "$T/root/etc/resolv.conf"; cp -L /etc/resolv.conf "$T/root/etc/resolv.conf"  # the image links it to resolved

    chroot "$T/root" "$@"
}

image_chroot_cleanup() {
    local T=$1 loop=$2 m
    for m in root/proc root/sys root/dev root/ohmarchy root/ohmarchy-out root lower; do
        umount -l "$T/$m" 2>/dev/null || true
    done
    losetup -d "$loop" 2>/dev/null || true
    rm -rf "$T"
}
