---
name: run-automated-vm-setup
description: Explain and run an installed Omarchy VM created by the automated-vm-setup skill, using a normal QEMU desktop window.
---

# Run An Automated Omarchy VM

Use this skill when the user wants to start, see, use, or stop an installed VM that was created by `.agents/skills/automated-vm-setup/SKILL.md`.

## User Experience Goal

The user should see a normal QEMU window appear on their desktop. Do not require them to connect with VNC for routine use.

Use VNC only as an internal automation/testing mechanism, not as the user-facing launch path.

## Locate The VM

Installed VMs created by `automated-vm-setup` live under:

```text
release/vm-test/<timestamp>/
```

The most important files are:

- `boot-installed.sh` starts the installed VM in a GTK window.
- `omarchy-test.qcow2` is the installed VM disk.
- `OVMF_VARS.fd` stores the VM firmware variables.
- `boot-installed.log` captures launcher output if the helper is started detached.

If the user does not provide a timestamp, inspect `release/vm-test/` and prefer the newest directory that contains both `boot-installed.sh` and `omarchy-test.qcow2`.

## Start The VM

Run the boot helper directly from the repo root:

```bash
./release/vm-test/<timestamp>/boot-installed.sh
```

This should open a QEMU GTK window on the desktop.

For a detached launch that does not tie up the current terminal:

```bash
./release/vm-test/<timestamp>/boot-installed.sh > release/vm-test/<timestamp>/boot-installed.log 2>&1 &
```

Then report the PID from the shell and verify QEMU is running:

```bash
pgrep -af qemu-system-x86_64
```

## What To Tell The User

After starting the VM, tell the user:

- A QEMU window should now be visible on the desktop.
- The VM may take a little while to reach the greeter after first boot.
- The configured username, password, and hostname if known.
- The PID to kill if they want to stop it manually.

Example response:

```text
The VM is running in a QEMU window.
Login: test / abcd1234
Hostname: example
PID: 484287
Stop it with: kill 484287
```

## Stop The VM

First identify the running QEMU process:

```bash
pgrep -af qemu-system-x86_64
```

Terminate only the VM process that belongs to the requested VM:

```bash
kill <pid>
```

Verify it stopped:

```bash
pgrep -af qemu-system-x86_64
```

Do not kill unrelated QEMU processes unless the user explicitly asks.

## If The Window Does Not Appear

Check that the desktop environment variables are present:

```bash
printenv DISPLAY WAYLAND_DISPLAY XDG_RUNTIME_DIR
```

Check the boot helper log:

```bash
tail -n 80 release/vm-test/<timestamp>/boot-installed.log
```

Common causes:

- The helper was started from a non-graphical environment.
- The previous VM is still running and holding the disk or SSH port.
- QEMU cannot find OVMF firmware; set `OMARCHY_OVMF_CODE` if needed.
- SSH forwarding port `2222` is already in use; launch with `OMARCHY_VM_SSH_PORT=<port>`.

## Custom Launch Options

The generated `boot-installed.sh` supports these environment variables:

- `OMARCHY_VM_SSH_PORT` sets host SSH forwarding port, default `2222`.
- `OMARCHY_VM_SMP` sets VM CPU count, default `4`.
- `OMARCHY_VM_MEMORY` sets VM memory in MiB, default `8192`.
- `OMARCHY_OVMF_CODE` overrides the OVMF code firmware path.

Examples:

```bash
OMARCHY_VM_MEMORY=12288 ./release/vm-test/<timestamp>/boot-installed.sh
```

```bash
OMARCHY_VM_SSH_PORT=2223 ./release/vm-test/<timestamp>/boot-installed.sh
```

## Important Notes

- Do not ask the user to connect with VNC for normal use.
- Do not rerun the installer when the user only wants to start an already-created VM.
- Do not modify the VM disk unless explicitly asked.
- Generated VM artifacts are ignored by git and should not be committed.
