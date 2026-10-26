# ohmarchy: Omarchy on HarmonyOS

Running [Omarchy](https://omarchy.org) (Arch Linux + Hyprland) on a HarmonyOS PC,
driven from a Linux host over `hdc`. Developed on a HUAWEI MateBook Fold
(HarmonyOS 7.0) with the AArch64 Omarchy build from
[riverscn/omarchy-aarch64-image](https://github.com/riverscn/omarchy-aarch64-image).

| Route | What runs on the HarmonyOS machine | Status |
|---|---|---|
| **A. Linux engine apps**: [docs/linux-engine-apps.md](docs/linux-engine-apps.md) | Omarchy's neovim setup and CLI tools inside HarmonyOS's Linux engine, each in a native HarmonyOS window | Works |
| **B. Whole OS in the Oseasy VM**: [docs/oseasy-whole-os.md](docs/oseasy-whole-os.md) | The complete Omarchy AArch64 OS in the Oseasy VM app, on a patched 7.2 kernel | The Hyprland desktop works (800x600, software rendering), with the VM's keyboard, touchpad and touch screen adapted; see status |

What was tried and why other paths fail: [docs/findings.md](docs/findings.md).

## Route B quick start

On a Linux host (`hdc` from the OpenHarmony SDK, USB debugging enabled on the
HarmonyOS machine):

```sh
oseasy/10-fetch-inputs.sh       # Omarchy image (3.7 GB), Debian 6.1 kernel debs, Debian netinst ISO
oseasy/20-build-modules.sh      # SVGA driver + efidrm module against Debian's 6.1 headers
oseasy/25-build-kernel-7.2.sh   # patched 7.2 kernel in a container (needed for the desktop)
oseasy/30-prepare-image.sh      # qcow2 -> raw, read the partition layout and root UUID
oseasy/27-build-aquamarine.sh   # aquamarine without the per-frame renderer retry (root, in the image's root)
oseasy/28-build-extras.sh       # ohmarchy-glfinish.so and the Pinyin packages (root, in the image's root)
oseasy/40-build-boot.sh         # boot entries (UKIs), Limine menu and first-boot files into the image's ESP
oseasy/50-make-installer-iso.sh # Debian netinst ISO carrying the Omarchy disk image
oseasy/60-push-iso.sh           # copy the ISO to the HarmonyOS Download folder
```

Then follow the install steps in [docs/oseasy-whole-os.md](docs/oseasy-whole-os.md#install-in-oseasy).
Settings live in `oseasy/config.sh`; outputs go to `work/`.

Host tools: bash, python3, curl, unzip, bsdtar (libarchive), cpio, gzip,
qemu-img, sfdisk/blkid (util-linux), mtools, xorriso, kmod (depmod), make,
clang (with the `aarch64` target, any recent version), hdc; docker or podman
for the 7.2 kernel. 27 and 28 need root with btrfs and overlayfs on an aarch64
host (`docker run --privileged` on an Apple silicon Mac works).

## Layout

```
oseasy/            build pipeline for route B (10..60), config, boot menu template
  initramfs/       overlay added to the 6.1 initramfs: network shell, GPU modes, first-boot module install
  installer/       scripts run in the Debian installer's rescue shell inside the VM
  lib/             uki.py (assemble UKIs), modsubset.py (module + dependency subset), image-chroot.sh
  root/            first-boot setup for the installed system, and the VM's input services
  aquamarine/      aquamarine patch and its build in the image's root
  extras/          glfinish.c and the Pinyin packages' fetch, built in the image's root
  hyprland/        Hyprland patch for upstream (software rendering on firmware framebuffers)
kernel/            patched 7.2 kernel: ID registers added after v6.1 read as zero, config fragment
driver/
  vmwgfx-oseasy/   vmwgfx for the HarmonyOS SVGA device (indexed MMIO, display-unit selection)
  efidrm/          omarchy_efidrm: simpledrm on the EFI framebuffer for the Debian 6.1 kernel
tools/fold/        hdc helpers: screenshots, taps, keys, typing into the VM, guest shell, file copy
tools/kbuild/      build out-of-tree arm64 modules against Debian headers with clang
linux-engine/      route A install scripts (run inside the Linux engine container)
docs/
```

## License

`driver/` and `kernel/` are derived from the Linux kernel and are GPL-2.0. Upstream projects
used by the scripts keep their own licenses.
