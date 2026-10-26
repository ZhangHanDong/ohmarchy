# Findings

Observations from bringing Omarchy to a HarmonyOS PC (MateBook Fold,
HarmonyOS 7.0). Each was observed on the device unless marked otherwise.

## HarmonyOS virtualization

- VMs run under the system's `vm_manager` with StratoVirt on the HarmonyOS
  hypervisor. A VM created through the private interfaces directly (no app) can
  boot and even render Omarchy's desktop, but it cannot show it: only a
  HarmonyOS app (UIAbility) can own a window, and the VM manager's caller
  checks exclude ordinary apps. That route ends at a serial console.
- Third-party VM apps such as Oseasy do get a window, so they are the way to
  run a whole OS with a visible screen.

## The Oseasy VM

- Machine: StratoVirt `virt`, GICv3, 6 vCPUs, 8 GB, UEFI with disk-first boot.
  Devices: virtio-blk (qcow2), xHCI with USB keyboard and tablet,
  virtio-multitouch, virtio-net, virtio-balloon, vhost-user-fs (tag
  `shared_dir`), an audio shared-memory device, virtio-serial ports for the
  vendor agent, and `svga-pci`.
- `svga-pci` is a VMware SVGA II device (`15ad:0405`) with a 16-byte **MMIO**
  BAR0 (registers), a 256 MiB VRAM BAR1 and a 2 MiB FIFO BAR2. Stock `vmwgfx`
  expects I/O ports and fails with "Unsupported SVGA ID 0xffffffff". With
  indexed MMIO (`driver/vmwgfx-oseasy`, `hvm_mmio=1`) it binds: SVGA 2, 3D,
  DX/SM4, guest-backed objects, screen object 2. It reports no screen targets,
  DEPTH 0 and BYTES_PER_LINE 0, and its preferred mode matches the window size.
- The UEFI GOP framebuffer lives in VRAM, and efifb works. Firmware, GRUB,
  Limine and the 6.1 kernel console are all visible.
- Once a guest driver enables SVGA mode, the window stops updating. Output
  through screen objects or the legacy display unit (with the depth fix) never
  appears. The host does set up a Vulkan swapchain at that point.
- The NIC is bridged to `172.16.100.1/24` on the HarmonyOS side, with no DHCP.
  The `hdc` shell can connect to the guest but cannot listen, and `hdc rport`
  binds 127.0.0.1 only.
- File sharing (virtiofs) is configured only for Windows guests with Oseasy's
  tools: `virtiofsd` runs without a shared directory. The serial console goes to
  a host log that the `hdc` shell cannot read.
- The app expects a Windows install. Its progress page times out with
  安装过程出现异常, and the VM keeps running. Closing the VM leads to
  安装失败 → 再次安装, which recreates the disk.

## Kernel

- Kernels >= 6.5 hang early in this VM (Omarchy's 7.2.3, a community report
  covering 6.5 and 6.12). Debian's 6.1.0-50 boots.
- Cause: the community report bisected the hang to edc25898f0b6 ("arm64:
  cpufeature: add system register ID_AA64MMFR3_EL1", v6.5). The architecture
  requires unallocated ID registers to read as zero, but this hypervisor injects
  an undefined instruction instead. v6.5 reads ID_AA64MMFR3_EL1 in
  `__cpu_setup`, with the MMU off and before any console, hence the silent early
  hang. 7.2 reads five ID registers that 6.1 never touches (MMFR3, MMFR4, PFR2,
  FPFR0, ISAR3), in `__cpu_setup`, `__cpuinfo_store_cpu()` and
  `__read_sysreg_by_encoding()`. With `kernel/0100-*.patch`, which reads them as
  zero, 7.2.11 boots; the unpatched kernel with earlycon prints nothing.
- StratoVirt freezes the VM when the guest writes zero to the virtio-pci
  extended feature words 2 and 3, which 7.2 does and 6.1 does not
  (`kernel/0101`).
- Under 7.2 no device in this VM raises an interrupt: the virtio ISR reads 0,
  the PCI status shows no INTx, the GIC SPI is enabled and never pending, and
  xhci commands time out. 6.1 gets INTx on the same SPIs. The cause is still
  open (`kernel/0102`, the GIC priority, is not it). `kernel/0103` polls instead:
  `virtio_ring.poll_us=1000` runs every virtqueue's callback from an hrtimer and
  `virtio_ring.poll_irqs=15` the handlers of Linux irq 15 (xhci: keyboard and
  tablet), every millisecond. With that, the whole desktop works.
- Debian 6.1 arm64 has neither `CONFIG_SYSFB_SIMPLEFB` nor simpledrm, so the
  only KMS options are the SVGA driver or `driver/efidrm`.
- Omarchy's root on a foreign kernel needs that kernel's modules. Without them
  ufw fails halfway and leaves the INPUT policy at DROP. The initramfs overlay
  installs the 6.1 modules on first boot.
- busybox chooses the applet from its file name, so a copy named anything other
  than `busybox` fails with "applet not found".

## Display (7.2, efidrm)

- The UEFI GOP offers a single mode, 800x600. Limine's `resolution:` (tried
  1600x1200 and 1024x768) falls back to it, so efidrm, and Hyprland, run at
  800x600@60; Oseasy scales that to the window.
- Hyprland renders with llvmpipe on 6 vCPUs. Light work reaches 60 commits a
  second on about two cores; animations, blur and shadows cost the most, so the
  setup turns them off (Omarchy's own VM flag, which the image predates).
- aquamarine needs an EGL renderer on every DRM device unless it is evdi. A
  firmware framebuffer has none, so it retried `initMgpu` on every commit,
  reopening the node, creating a GBM device and scanning EGL devices before
  failing again, with four errors in the log per frame (tens of MB an hour, in
  `/run/user`). `oseasy/aquamarine/0001-*.patch` treats firmware framebuffers
  like evdi.
- Ghosting (windows that stay after closing, trails around the pointer): the
  framebuffer memory itself held half-drawn frames. Dumping VRAM (BAR1 of the
  SVGA device, through `/sys/bus/pci/devices/0000:00:04.0/resource1`) showed the
  stale part with the staircase edge of llvmpipe's 64x64 tiles, while `grim`
  showed the finished frame; writing to VRAM directly shows up at once. Hyprland
  calls `glFinish` before a commit only on a software renderer, which it detects
  from the DRM driver's name, and efidrm is not on its list. Without explicit
  sync (llvmpipe has no native fence) it ends the frame with `glFlush`, which
  llvmpipe does not wait on. A single commit, like closing a window, then leaves
  the half-drawn frame on screen until the next one. `oseasy/extras/glfinish.c`
  works around it; `oseasy/hyprland/0001-*.patch` is the fix for upstream. The
  faster patched aquamarine made it worse only because it commits sooner.

## Input

- Oseasy passes the HarmonyOS keyboard as a USB keyboard. HarmonyOS keeps its own
  Caps Lock, Num Lock and Scroll Lock state and compares it with the guest's
  LEDs; when they differ it wraps every key in an extra press and release of the
  lock key, 1 to 3 ms long. An XKB remap such as `caps:super` never toggles the
  LED, so after one press every key comes wrapped, which also releases a held
  Caps Lock. The compositor sets the LEDs from its own XKB state, so it has to
  be kept off the real keyboard (`oseasy/root/ohmarchy-caps-super`).
- HarmonyOS keeps some shortcuts: SUPER reaches the guest, but the L of SUPER + L
  does not.
- Touches on the HarmonyOS screen arrive as a single absolute pointer (the USB
  tablet), however many fingers: no multi-finger gesture can be seen in the
  guest.
- The touchpad arrives as "StratoVirt Virtio Multitouch", which libinput takes
  for a touchpad (POINTER and BUTTONPAD), with three slots: three-finger swipes
  work, four fingers never arrive. Two fingers are scrolling, and Hyprland's
  scroll binds (`mouse_left`/`mouse_right`) react to wheels only, not to finger
  scrolling.

## Packages and network

- The image's package databases date from the image build; the Arch Linux ARM
  mirrors, Tsinghua's included, keep only current versions, so packages new to
  the image have to come from a current database. Installing one from it is a
  partial upgrade: fcitx5-qt from a current database, for example, is built for
  a newer Qt than the image has, and Qt's input method plugin needs the exact Qt.
- github.com is unreachable from the VM in China, and the image's Omarchy
  repository is GitHub releases (`riverscn/omarchy-pkgs-aarch64`), so
  `omarchy-update` stops at syncing it. Tsinghua's Arch Linux ARM mirror is
  fast; the original and Omarchy's arm-mirror are slow.

## Host link

- A USB-C cable between the host laptop and the HarmonyOS machine keeps
  renegotiating power and alternate modes, which drops `hdc` every 10 to 45 s.
  A USB 2.0 data cable avoids that. Alternatively use wireless hdc:
  `hdc tmode port 5555`, then `hdc tconn <ip>:5555`. That needs a network
  without client isolation.

## Route A (Linux engine)

- The Linux engine container exposes the machine's GPU as "Virtio-GPU Venus".
  The third-party launcher's X11 bridge composites each app into its own
  HarmonyOS window. Terminal apps work well; a nested Hyprland session does
  not fit this model.
