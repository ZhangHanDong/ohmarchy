# Route B: the whole Omarchy OS in the Oseasy VM

[Oseasy虚拟机](https://appgallery.huawei.com/) (`com.oseasy1.ohvm`, AppGallery) is a
Windows-on-ARM VM app for HarmonyOS PCs. It runs StratoVirt on the HarmonyOS
hypervisor and shows the guest in a native window. It accepts any ISO after two
warnings, so it can run a complete Omarchy AArch64 install.

## Status

Verified on a MateBook Fold, HarmonyOS 7.0.0.111, Oseasy 3.1.0:

- The Omarchy disk image installs from a remastered Debian installer ISO.
- The patched 7.2.11 kernel (`oseasy/25-build-kernel-7.2.sh`, `kernel/`) boots
  Omarchy to the Hyprland desktop on efidrm (the EFI framebuffer, 800x600,
  software rendering). It reads the ID registers added after v6.1 as zero, the
  cause of the early hang of every kernel >= 6.5 here, and polls virtqueues and
  the xhci interrupt, since no device interrupt reaches 7.2 in this VM (see
  [findings](findings.md#kernel)).
- First boot is unattended up to Omarchy's own wizard: the setup installs the
  kernel as a package, grows the root to the disk, and adapts the desktop to the
  VM (see [the desktop in the VM](#the-desktop-in-the-vm)).
- The network root shell works in the initramfs and in the running system.
- The Debian 6.1 entries still boot to a text console (no desktop: Debian's 6.1
  has no KMS driver for this framebuffer).

Open:

- **Interrupts under 7.2.** The polling works, but costs a little CPU and adds
  up to a millisecond of latency; the cause is not found.
- **Resolution.** The firmware's GOP has only 800x600. The SVGA driver
  (`driver/vmwgfx-oseasy`) binds the Oseasy SVGA device with 3D, DX/SM4 and
  guest-backed objects and could follow the window size, but once it enables
  SVGA mode Oseasy stops refreshing the window.
- **Updates.** `omarchy-update` needs github.com (the image's Omarchy
  repository), which is unreachable from China without a proxy.
- **The VM itself.** Closing the Oseasy window wipes the disk (see
  [Reinstall or reset](#reinstall-or-reset)); minimize it instead.

## Build

See the quick start in the [README](../README.md). The result is
`work/omarchy-install.iso`: the Debian 12 arm64 netinst ISO plus
`omarchy.raw.gz` (the Omarchy disk with ohmarchy's boot entries and first-boot
files in its ESP), `omarchy-write.sh` and `write-esp.sh`.

The desktop needs the optional steps too:

| Script | Output | Installed by |
|---|---|---|
| `25-build-kernel-7.2.sh` | the patched 7.2 kernel: UKIs and the `linux-ohmarchy-oseasy` package | `40-build-boot.sh` (entries), the setup (package) |
| `27-build-aquamarine.sh` | aquamarine with `oseasy/aquamarine/0001-*.patch` | the setup, over the same upstream version |
| `28-build-extras.sh` | `ohmarchy-glfinish.so` and the Pinyin packages | the setup |

27 and 28 build inside a throwaway copy of the image's root
(`oseasy/lib/image-chroot.sh`), so they need root, btrfs and overlayfs on an
aarch64 host, for example `docker run --privileged` on an Apple silicon Mac.

Boot entries written to the ESP (`oseasy/limine.conf.in`):

| Entry | Kernel command line extra | Purpose |
|---|---|---|
| EFI framebuffer | (none) | console on efifb, Omarchy userspace (the default without the 7.2 kernel) |
| hold in initramfs | `omarchy_hold=1` | stops before the root mount for debugging; `touch /run/omarchy/go` continues |
| efidrm KMS | `omarchy_gpu=efidrm` | experimental: `omarchy_efidrm` provides card0 on the EFI framebuffer |
| SVGA 3D driver | `omarchy_gpu=svga` | experimental: `vmwgfx` with `hvm_mmio=1 hvm_display=2` |
| stock 7.x kernel | | Omarchy's own UKI, kept for reference (hangs) |
| patched 7.2 kernel, efidrm KMS | the polling options | default: 7.2.11 from `25-build-kernel-7.2.sh`, with ohmarchy's initramfs layers (network shell, first-boot setup) |
| patched 7.2 kernel, earlycon | the above plus `earlycon=efifb keep_bootcon ignore_loglevel` | the same, printing from early boot on |

The last two are added, and the first of them made the default, only when
`$WORK/k72` exists, that is when
`oseasy/25-build-kernel-7.2.sh` ran before `40-build-boot.sh`. It builds in a
container (`docker` by default, `DOCKER=podman` works too; about an hour on 8
cores, ~25 GB), and on an x86 host it cross-compiles.

## Install in Oseasy

1. Push the ISO: `oseasy/60-push-iso.sh` copies it to the Download folder (下载).
2. Open Oseasy虚拟机 → 立即创建 → **点击选择 ISO** → pick `omarchy-install.iso`
   in 下载 → it reports 镜像不符合要求 (系统架构: 未知) → 下一步 →
   **继续安装** → **仍要安装** → keep the default 6 cores / 8 GB / 128 GB →
   开始安装 (a low-battery prompt may appear; charge the machine).
3. The VM opens on the installer's GRUB. Choose *Advanced options → Rescue
   mode*, then: English → United States → American English → network
   autoconfiguration fails, so Continue → *Do not configure the network at this
   time* → hostname Enter → time zone Enter → "No partitions found" Continue →
   *Execute a shell in the installer environment* → Continue.
4. In the shell: `sh /cdrom/omarchy-write.sh` (writes the disk, about 12
   minutes), then `sync; reboot -f`. The VM boots its disk before the installer
   media, so it now comes up in the Limine menu.
5. Oseasy's main window waits for a Windows install and later reports
   安装过程出现异常. Press 确定; the VM keeps running.

Typing into the VM from the host: `tools/fold/type.sh 'command'` (keep
commands short and without single quotes), `tools/fold/key.sh 2054` (Enter),
`tools/fold/shot.sh name` (screenshot).

## First boot

Limine boots the patched 7.2 kernel by default (or **EFI framebuffer**
without it). The initramfs:

- gives the VM NIC `172.16.100.2/24` (the HarmonyOS side of the bridge is
  `172.16.100.1`; there is no DHCP) and serves a root shell on tcp/5000;
- installs Debian's 6.1 modules into Omarchy's root from the ESP
  (`/ohmarchy/modules-<kver>.tar.gz`), since the root only carries modules for
  Omarchy's own kernel;
- blacklists autoloading of `vmwgfx` (its probe takes the framebuffer and then
  fails on this device), keeps NetworkManager off the VM NIC, allows the bridge
  subnet in ufw, and installs `omarchy-netremote.service` for the running
  system;
- copies ohmarchy's first-boot setup (`oseasy/root`) into the root.

`ohmarchy-oseasy-system.service` then runs before Omarchy's provisioning, and
`ohmarchy-oseasy-user.service` after it, before the login screen; both run
`ohmarchy-oseasy-setup` on every boot, and every step is idempotent. The system
step installs the 7.2 kernel package (so Omarchy's limine-update builds its
entry with the polling options), aquamarine, `ohmarchy-glfinish.so`, the Pinyin
packages and the pacman mirrors, enables the input services and grows the root
to the disk. The user step sets up each user's desktop for the VM.

Omarchy's first-boot wizard (owner account, keyboard, hostname, time zone) runs
on tty1 before SDDM; answer it with the keyboard in the VM window.

## The desktop in the VM

What the first-boot setup changes, and why (details in [findings](findings.md)):

| What | How to use it | Done by |
|---|---|---|
| Frames are finished before they are shown (no ghosting) | | `ohmarchy-glfinish.so`, preloaded into the session's and the greeter's Hyprland |
| No per-frame renderer retry (and log flood) on efidrm | | aquamarine with `oseasy/aquamarine/0001-*.patch` |
| No animations, blur or shadows (all rendering is on the CPU) | `omarchy toggle animations` turns them back on | toggle `no-animations.lua` |
| Caps Lock is SUPER, since HarmonyOS keeps some SUPER shortcuts (SUPER + L) | Caps Lock + key; both Shifts toggle Caps Lock; Right Alt is compose | `ohmarchy-caps-super.service`, toggle `ohmarchy-oseasy-input.lua` |
| Touchpad gestures (three fingers at most) | three fingers left/right: workspaces; SUPER + three fingers: windows of the scrolling layout | toggle `ohmarchy-oseasy-input.lua` |
| Touch-screen edge swipes (the screen reaches the VM as one pointer) | from the right/left edge inwards: next/previous workspace; along the bottom edge: next window | `ohmarchy-edge-swipe.service` |
| Pinyin input method, Simplified Chinese glyphs | Ctrl + Space switches; Shift for English while in Pinyin | `fcitx5-chinese-addons`, the user's Fcitx profile and fontconfig |
| Fast package mirror in China | | `/etc/pacman.d/mirrorlist`: Tsinghua first, the original as the fallback |

The toggles live in `~/.local/state/omarchy/toggles/hypr/`, which Hyprland
loads after the user's config. The two input services grab their device and
pass it on through a virtual one. If `ohmarchy-caps-super` stops, the real
keyboard goes back to the compositor; if `ohmarchy-edge-swipe` stops, the tablet
does. `sudo systemctl disable --now` turns either off for good (the setup enables
them once). The first Caps Lock combination after a boot can be lost while the
LEDs come into step with HarmonyOS's lock state.

## Network shell

From the host: `tools/fold/guest.sh 'uname -a; ip -br addr'`. The HarmonyOS
shell may open outgoing TCP connections (`netcat`) but not listening sockets,
so the guest always listens:

| Port | Service |
|---|---|
| 5000 | root shell (busybox `tcpsvd`) |
| 5001 | upload: first line is the destination path, then the bytes |
| 5100-5899 | one-shot transfers used by `tools/fold/guest-put.sh` and `guest-get.sh` (a fresh port each, checked by sha256) |

## Reinstall or reset

- Closing the VM window asks 创建尚未完成，确定退出 → 确定 → 安装失败 →
  **再次安装** recreates the disk and boots the ISO again. This wipes the
  Omarchy disk.
- `write-esp.sh` rewrites only the ESP from the ISO and keeps the root
  filesystem. It needs the installer booted again.
- To reset the app completely: `hdc shell bm clean -n com.oseasy1.ohvm -d`.
