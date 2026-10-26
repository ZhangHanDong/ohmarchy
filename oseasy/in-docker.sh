#!/usr/bin/env bash
# in-docker.sh STEP...: run oseasy/<STEP>.sh in a Debian container, for hosts
# without the tools (macOS among them). Example, after 25-build-kernel-7.2.sh:
#
#   oseasy/in-docker.sh 10-fetch-inputs 20-build-modules 30-prepare-image \
#       27-build-aquamarine 28-build-extras 40-build-boot 50-make-installer-iso
#
# The work tree is a docker volume ($OHMARCHY_VOLUME), not the host's work/:
# 27 and 28 loop-mount the image's btrfs root, which needs a Linux filesystem
# and --privileged. The patched 7.2 kernel from the host's work/k72 (25 builds
# it in a container of its own) is copied in first, and the ISO is copied back
# to work/. 25 and 60 (hdc) run on the host. Tried on an Apple silicon Mac with
# 27, 28, 40 and 50; 10, 20 and 30 have not been run this way yet.
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
root=$(dirname "$here")
: "${DOCKER:=docker}"
: "${OHMARCHY_VOLUME:=ohmarchy-work}"
: "${OHMARCHY_BUILD_IMAGE:=debian:trixie}"

(( $# )) || { echo "usage: in-docker.sh STEP..." >&2; exit 2; }
for s in "$@"; do
    case "$s" in
        25-build-kernel-7.2|60-push-iso) echo "$s runs on the host" >&2; exit 2 ;;
    esac
    [[ -f $here/$s.sh ]] || { echo "no such step: $s" >&2; exit 2; }
done
mkdir -p "$root/work"

"$DOCKER" run --rm --privileged \
    -v "$OHMARCHY_VOLUME:/work" -v "$root:/ohmarchy" -v "$root/work:/host-work" \
    -e WORK=/work -e STEPS="$*" "$OHMARCHY_BUILD_IMAGE" bash -euo pipefail -c '
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends ca-certificates curl unzip libarchive-tools \
    cpio gzip pigz zstd qemu-utils fdisk util-linux mount mtools xorriso kmod python3 \
    make clang lld >/dev/null
if [ -s /host-work/k72/kver ]; then
    rm -rf /work/k72 && mkdir -p /work/k72/modroot
    cp /host-work/k72/Image /host-work/k72/kver /host-work/k72/config /host-work/k72/modules-*.tar.gz /work/k72/
    cp /host-work/k72/*.pkg.tar.* /work/k72/ 2>/dev/null || true
    tar -xzf "/work/k72/modules-$(cat /work/k72/kver).tar.gz" -C /work/k72/modroot
fi
cd /ohmarchy
for s in $STEPS; do echo "===== $s"; bash "oseasy/$s.sh"; done
case " $STEPS " in
    *" 50-make-installer-iso "*) cp /work/omarchy-install.iso /work/omarchy-install.iso.sha256 /host-work/ ;;
esac
'
