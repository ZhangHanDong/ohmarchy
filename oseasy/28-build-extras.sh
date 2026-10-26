#!/usr/bin/env bash
# Build the Oseasy extras (oseasy/extras): ohmarchy-glfinish.so and the Pinyin
# input method's packages, which ohmarchy-oseasy-setup installs on first boot.
# Output: $WORK/extras/{ohmarchy-glfinish.so,pkgs/}. Made inside the image's own
# root (lib/image-chroot.sh), like 27-build-aquamarine.sh.
set -euo pipefail
. "$(dirname "$0")/config.sh"
. "$(dirname "$0")/lib/image-chroot.sh"
need losetup mount chroot
cd "$WORK"; . ./image.env

rm -rf "$WORK/extras"
image_chroot extras "$OHMARCHY_ROOT/oseasy/extras" "$WORK/extras" /ohmarchy/build-in-root.sh /ohmarchy-out
ls -laR "$WORK"/extras/
