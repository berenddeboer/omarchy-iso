---
name: boot-iso
description: Build or boot the Omarchy ISO in a normal visual QEMU window for manual installer testing.
---

# Boot The Omarchy ISO Manually

Use this skill when the user wants to visually boot the Omarchy ISO installer in QEMU and manually test the full install flow.

Do not use the automated VM test harness for this. `bin/omarchy-iso-vm-test` drives the installer automatically and is for unattended verification.

## User Experience Goal

The user should see a normal QEMU GTK window with the live ISO installer, then interact with the installer themselves.

## Rebuild And Boot

From the repository root, rebuild from the local Omarchy checkout and accept the boot prompt:

```bash
OMARCHY_PATH="$HOME/src/omarchy" ./bin/omarchy-iso-make --local-source
```

When prompted with `Boot release/omarchy-...-master.iso?`, answer yes.

This uses `bin/omarchy-iso-boot` to launch the ISO visually.

## Boot An Existing ISO

To boot a specific ISO manually:

```bash
./bin/omarchy-iso-boot release/omarchy-2026.05.02-x86_64-master.iso
```

To choose from available ISOs interactively:

```bash
./bin/omarchy-iso-boot
```

## Clean Manual Disk

The manual boot helper uses a temporary disk:

```text
/tmp/omarchy-iso-boot.qcow2
```

For a clean install attempt, remove the old disk and OVMF variable store first:

```bash
rm -f /tmp/omarchy-iso-boot.qcow2 /tmp/OVMF_VARS.4m.fd
./bin/omarchy-iso-boot release/omarchy-2026.05.02-x86_64-master.iso
```

Use `reuse` only when intentionally keeping the previous temporary disk:

```bash
./bin/omarchy-iso-boot release/omarchy-2026.05.02-x86_64-master.iso reuse
```

Fresh installs boot the ISO once, then prefer the installed disk after the installer reboots. Reused disks should boot the installed disk first.

## ZFS Selection

The initial boot menu does not choose ZFS. Boot the normal/default Omarchy ISO entry.

ZFS is selected later inside the installer at the `Select root filesystem` prompt:

```text
ZFS (unencrypted, experimental)
```

## QEMU Display Fixes

The manual boot helper should avoid OpenGL because some desktops lack the required GTK GL/DMABUF support. Use non-GL GTK and explicit VirtIO scanout:

```bash
-device virtio-vga,xres=1280,yres=800
-display gtk,gl=off,zoom-to-fit=on
```

If the helper crashes with messages like these, remove GL from the QEMU display path:

```text
qemu: GtkGLArea console lacks DMABUF support.
epoxy_get_proc_address: Assertion `0 && "Couldn't find current GLX or EGL context."' failed.
```

If the VM window opens but shows a black screen or says `display output is not active`, ensure the ISO is booted before the empty disk and the video device has an explicit scanout size:

```bash
-device virtio-blk-pci,drive=drive0,bootindex=1
-device ide-cd,drive=cdrom0,bootindex=2
-boot once=d,menu=on
-device virtio-vga,xres=1280,yres=800
```

If that still fails, switch the manual helper to plain VGA as the fallback:

```bash
-vga std
```

## ZFS Boot Messages

Older ZFS test ISOs may briefly show this during boot:

```text
ERROR: device 'ZFS=zroot/ROOT/default' not found. Skipping fsck.
no pools available to import
```

This can be non-fatal if the system continues to boot. The first line comes from the generic `fsck` initramfs hook, which is not needed for ZFS roots. Future ZFS installs should omit the `fsck` hook from the ZFS initramfs hook list.

## Distinguish Related Tools

Use `bin/omarchy-iso-boot` for manual visual ISO installer testing.

Use `bin/omarchy-iso-vm-test` only for automated installer verification.

Use `release/vm-test/<timestamp>/boot-installed.sh` only to boot an already-installed VM produced by the automated VM test flow.

## Important Notes

- Do not ask the user to connect with VNC for manual ISO testing.
- Do not use the automated test harness when the user wants to manually click/type through the installer.
- Generated ISO, VM disk, screenshot, and log artifacts should stay under `release/` or `/tmp/` and should not be committed.
