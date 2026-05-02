---
name: automated-vm-setup
description: Create and verify a fully automated local Omarchy VM install from this ISO repo using the local ~/src/omarchy source checkout.
---

# Automated Omarchy VM Setup

Use this skill when the user wants a real local VM installed from the Omarchy ISO, with the installer driven automatically and the resulting VM made available as a normal desktop QEMU window.

## Goals

- Build the ISO from the local Omarchy source checkout at `~/src/omarchy`.
- Boot the ISO in a real KVM/QEMU VM.
- Drive the live installer prompts automatically.
- Detect installation progress and errors from the real VM display/serial state.
- Preserve artifacts under `release/vm-test/<timestamp>`.
- Provide the user a bootable installed VM disk and a GTK boot helper, not a VNC-only experience.

## Prerequisites

- Run from the `omarchy-iso` repo root.
- Confirm `~/src/omarchy` exists unless the user explicitly provides another local source path.
- Confirm KVM is available with `/dev/kvm` readable and writable.
- Confirm `qemu-system-x86_64`, `qemu-img`, `expect`, `python3`, and `docker` are available.
- Do not rely on host-side `gum` for automation.

## Build And Install A New VM

Use `bin/omarchy-iso-vm-test` for the real automated install. It builds from local source by default via `OMARCHY_TEST_OMARCHY_PATH`, boots the resulting ISO in KVM, drives the visible installer UI, and exits after installation completes and the VM reboots.

```bash
OMARCHY_TEST_USER=test \
OMARCHY_TEST_PASSWORD=abcd1234 \
OMARCHY_TEST_HOSTNAME=example \
OMARCHY_TEST_INTERACTIVE_ON_FAILURE=0 \
./bin/omarchy-iso-vm-test
```

To reuse the current/latest ISO instead of rebuilding:

```bash
OMARCHY_TEST_USER=test \
OMARCHY_TEST_PASSWORD=abcd1234 \
OMARCHY_TEST_HOSTNAME=example \
OMARCHY_TEST_INTERACTIVE_ON_FAILURE=0 \
./bin/omarchy-iso-vm-test --no-build --iso release/omarchy-2026.05.01-x86_64-master.iso
```

The installer's default filesystem path is btrfs. No extra filesystem argument is needed for the normal btrfs install.

## Successful Result

A passing run prints prompt screenshots as it drives the installer, then ends with lines like:

```text
Waiting for Omarchy installation to finish
Detected Omarchy install completion marker
VM exited after install completion
```

The resulting installed disk is:

```text
release/vm-test/<timestamp>/omarchy-test.qcow2
```

Important artifacts in the same directory:

- `serial.log`
- `screen.txt`
- `screen-history.log`
- `*_prompt.ppm` screenshots
- `OVMF_VARS.fd`
- `run.env`

## If The Install Fails

Use the run artifacts first.

Check `screen.txt` for the last visible installer screen.

Check `screen-history.log` for installer progress and messages such as `Installation completed without any errors`.

Check `serial.log` for boot, shutdown, traceback, pacman, archinstall, and QEMU errors.

If debugging interactively is useful, rerun without `OMARCHY_TEST_INTERACTIVE_ON_FAILURE=0`; the runner will keep the VM available on failure.

## User-Facing Boot Helper

After a successful automated install, create a GTK boot helper next to the disk so the user gets a normal desktop window instead of VNC.

Use this template, replacing `<timestamp>` with the artifact directory name:

```bash
#!/bin/bash
set -euo pipefail

disk="/home/berend/src/omarchy-iso/release/vm-test/<timestamp>/omarchy-test.qcow2"
ovmf_vars="/home/berend/src/omarchy-iso/release/vm-test/<timestamp>/OVMF_VARS.fd"
ovmf_code="${OMARCHY_OVMF_CODE:-}"
ssh_port="${OMARCHY_VM_SSH_PORT:-2222}"
smp="${OMARCHY_VM_SMP:-4}"
memory="${OMARCHY_VM_MEMORY:-8192}"

if [[ -z "$ovmf_code" ]]; then
  while IFS= read -r data_dir; do
    if [[ -f "${data_dir%/}/edk2-x86_64-code.fd" ]]; then
      ovmf_code="${data_dir%/}/edk2-x86_64-code.fd"
      break
    fi
  done < <(qemu-system-x86_64 -L help 2>/dev/null || true)
fi

if [[ -z "$ovmf_code" ]]; then
  for path in \
    /usr/share/edk2/x64/OVMF_CODE.4m.fd \
    /usr/share/edk2/x64/OVMF_CODE.fd \
    /usr/share/edk2-ovmf/x64/OVMF_CODE.fd \
    /usr/share/qemu/edk2-x86_64-code.fd; do
    if [[ -f "$path" ]]; then
      ovmf_code="$path"
      break
    fi
  done
fi

if [[ -z "$ovmf_code" ]]; then
  echo "Could not find OVMF_CODE firmware. Set OMARCHY_OVMF_CODE." >&2
  exit 1
fi

echo "Booting installed Omarchy VM"
echo "Disk: $disk"
echo "Display: QEMU GTK window"
echo "SSH forward: localhost:$ssh_port -> guest:22"

exec qemu-system-x86_64 \
  -enable-kvm \
  -machine q35,accel=kvm \
  -cpu host \
  -smp "$smp" \
  -m "$memory" \
  -display gtk,gl=off,zoom-to-fit=on \
  -device virtio-vga,xres=1280,yres=800 \
  -device virtio-keyboard-pci \
  -device virtio-mouse-pci \
  -drive if=pflash,format=raw,readonly=on,file="$ovmf_code" \
  -drive if=pflash,format=raw,file="$ovmf_vars" \
  -drive if=none,id=vdisk,file="$disk",format=qcow2,cache=writeback,discard=unmap \
  -device virtio-blk-pci,drive=vdisk,serial=omarchy-vm,bootindex=1 \
  -nic user,model=virtio-net-pci,hostfwd=tcp:127.0.0.1:"$ssh_port"-:22
```

Make it executable and syntax-check it:

```bash
chmod +x release/vm-test/<timestamp>/boot-installed.sh
bash -n release/vm-test/<timestamp>/boot-installed.sh
```

Start it detached when the user wants to see the VM:

```bash
release/vm-test/<timestamp>/boot-installed.sh > release/vm-test/<timestamp>/boot-installed.log 2>&1 &
```

Then verify QEMU is running:

```bash
pgrep -af qemu-system-x86_64
```

## Stopping The VM

Terminate the specific QEMU process by PID:

```bash
kill <pid>
```

Avoid killing unrelated QEMU processes unless the user explicitly asks.

## Notes

- `bin/omarchy-iso-boot` is only a manual smoke-test launcher. It uses host-side `gum` when no ISO is passed and is not the right tool for automated VM creation.
- The automation runner uses VNC internally for screenshots and keystrokes, but the user-facing installed VM should be launched with GTK.
- Keep generated VM disks and screenshots under `release/vm-test/`; this path is ignored by git.
- Do not commit generated VM disks, ISO artifacts, logs, or screenshots.
