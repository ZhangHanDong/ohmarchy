# Build configuration for the Oseasy whole-OS route (sourced by oseasy/*.sh).
# Every value can be overridden from the environment.
OHMARCHY_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
: "${WORK:=$OHMARCHY_ROOT/work}"                  # downloads and build outputs (~20 GB)

# Omarchy AArch64 VM image: https://github.com/riverscn/omarchy-aarch64-image
: "${OMARCHY_RELEASE:=v4.0.3-virt.1}"
: "${OMARCHY_QCOW2:=}"            # optional: use a local .qcow2 instead of the release

# Debian 6.1 kernel. Omarchy's own 7.x kernel (like every kernel >= 6.5 tried so
# far) hangs early inside the Oseasy VM; Debian's 6.1 boots.
: "${KVER:=6.1.0-50-arm64}"
: "${KPKG:=6.1.176-1}"
: "${KBUILD_SERIES:=6.1}"
: "${DEBIAN_MIRROR:=https://deb.debian.org/debian}"

# Patched 7.2 kernel (oseasy/25-build-kernel-7.2.sh, kernel/): Arch Linux ARM's
# linux-aarch64 plus kernel/0100-*.patch, which reads the ID registers added
# after v6.1 as zero. The hypervisor injects an undefined instruction for them,
# which is what hangs every kernel >= 6.5 here. The desktop needs it;
# 40-build-boot.sh adds its boot entries only when $WORK/k72 exists.
: "${K72_VER:=7.2.11}"
: "${K72_SERIES:=7.2}"
: "${ALARM_PKGBUILDS_COMMIT:=b7704835b2a0fd85b77eb7bc873d0a865e3e984b}"  # core/linux-aarch64 7.2.11-1
: "${K72_LOCALVERSION:=-ohmarchy}"                                       # uname -r: 7.2.11-ohmarchy-ARCH
: "${KERNEL_BUILD_IMAGE:=debian:trixie}"                                 # container that builds it
: "${DOCKER:=docker}"
# Under 7.2 no device in this VM raises an interrupt (cause still open; see
# docs/findings.md), so the 7.2 entries poll: every virtqueue, and the handlers
# of Linux irq 15 (xhci: keyboard and tablet), every millisecond. Needs the
# polling patch in the kernel (kernel/0103).
: "${K72_CMDLINE_EXTRA:=virtio_ring.poll_us=1000 virtio_ring.poll_irqs=15}"

# The installer ISO is only a carrier: Oseasy boots installer media, and the
# Debian rescue shell writes the Omarchy disk image to the VM disk.
: "${NETINST_URL:=https://cdimage.debian.org/cdimage/archive/12.15.0/arm64/iso-cd/debian-12.15.0-arm64-netinst.iso}"
: "${NETINST_ISO:=}"              # optional: local copy of the ISO above

# Out-of-tree module toolchain (clang targets aarch64 natively).
: "${CLANG:=clang}"

# hdc from the OpenHarmony SDK (toolchains/hdc); HDC_TARGET from `hdc list targets`.
: "${HDC:=hdc}"
: "${HDC_TARGET:=}"

# Kernel command line shared by all boot entries; ROOT_UUID is read from the image.
KCMD_BASE='rw rootflags=subvol=@ rootwait console=ttyAMA0,115200 console=tty1 loglevel=6'

die() { echo "error: $*" >&2; exit 1; }
need() { for t in "$@"; do command -v "$t" >/dev/null || die "missing tool: $t"; done; }
host_deb_arch() { case "$(uname -m)" in x86_64) echo amd64 ;; aarch64) echo arm64 ;; *) die "unsupported host $(uname -m)" ;; esac; }
