#!/usr/bin/env bash
# Build aquamarine with oseasy/aquamarine/0*.patch for the Omarchy image, as a
# pacman package that ohmarchy-oseasy-setup installs on first boot. Output:
#   $WORK/aquamarine/aquamarine-VER-REL.1-aarch64.pkg.tar.*
# It builds inside the image's own root (lib/image-chroot.sh), so the package
# matches the libraries it will run with.
set -euo pipefail
. "$(dirname "$0")/config.sh"
. "$(dirname "$0")/lib/image-chroot.sh"
need losetup mount chroot
cd "$WORK"; . ./image.env

rm -rf "$WORK/aquamarine"
image_chroot aquamarine "$OHMARCHY_ROOT/oseasy/aquamarine" "$WORK/aquamarine" /ohmarchy/build-in-root.sh /ohmarchy-out
ls -la "$WORK"/aquamarine/
