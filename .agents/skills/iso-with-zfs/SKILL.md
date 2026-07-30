---
name: iso-with-zfs
description: Build, update, and validate the private Quattro-on-ZFS Omarchy ISO and its paired Omarchy source branch.
---

# Quattro On ZFS

Use this skill for the private ZFS variant maintained on `quattro-on-zfs`. This is intentionally independent from upstream Omarchy filesystem support and is not a pull-request curation workflow.

## Paired Branches

The implementation spans two checkouts:

- `~/src/omarchy-iso`, branch `quattro-on-zfs`: installer UI, ZFS pool/datasets, ArchZFS packages, Limine boot intent, acceptance tests.
- `~/src/omarchy`, branch `quattro-on-zfs`: persistent mkinitcpio, PAM, Snapper, snapshot, hibernation, and pacman behavior packaged into the installed system.

Build with both branches checked out. Do not substitute published Quattro Omarchy packages because they contain the Btrfs-only finalizer.

## Storage Contract

- Unencrypted pool: `zroot`.
- Root: `zroot/ROOT/default`.
- Encrypted user home: `zroot/data/home/$USER`, using the login password, `keyformat=passphrase`, and `keylocation=prompt`.
- Disk-backed temporary directories: `zroot/data/tmp` at `/tmp` and `zroot/var/tmp` at `/var/tmp`.
- `tmp.mount` is masked so `/tmp` is never replaced by a RAM-backed tmpfs.
- No swapfile or hibernation configuration on ZFS.
- SDDM requires a password login so PAM can unlock the home dataset.
- Boot cmdline contains `root=ZFS=zroot/ROOT/default` and `zfs_boot_only=1`.
- Mkinitcpio uses `zfs filesystems`, omits `fsck` and `btrfs-overlayfs`, and embeds `/etc/hostid`.

## Updating From Quattro

Update the paired Omarchy branch first:

```bash
cd ~/src/omarchy
git fetch upstream
git switch quattro-on-zfs
git rebase upstream/quattro
```

Then update the ISO branch:

```bash
cd ~/src/omarchy-iso
git fetch upstream
git switch quattro-on-zfs
git rebase upstream/quattro
```

Resolve changes by preserving Quattro's common Archinstall, package, finalizer, Limine, and acceptance paths. Keep ZFS as a small storage-specific branch; never restore the old monolithic `.automated_script.sh` installer or PR-curation workflow.

After every upstream update, inspect these Btrfs-sensitive locations:

- `configs/airootfs/root/configurator`
- `orchestrator/context.py`
- `orchestrator/phases_impl.py`
- `orchestrator/zfs_storage.py`
- Omarchy `install/config/snapper.sh`
- Omarchy `etc/mkinitcpio.conf.d/omarchy_hooks.conf`
- Omarchy `bin/omarchy-hibernation-setup`
- Omarchy `bin/omarchy-snapshot`
- Omarchy `bin/omarchy-refresh-pacman`

## Verification

Run syntax and source tests first:

```bash
cd ~/src/omarchy
bash test/shell.d/zfs-test.sh

cd ~/src/omarchy-iso
bash -n configs/airootfs/root/configurator
bash -n builder/build-iso.sh
bash -n bin/omarchy-iso-test
python -m py_compile configs/airootfs/usr/share/omarchy-iso/orchestrator/*.py
git diff --check
```

Build with a local `omarchy-pkgs` checkout:

```bash
./bin/omarchy-iso-make --local-source "$HOME/src/omarchy" "$HOME/src/omarchy-pkgs" --no-cache --no-boot-offer
```

Run the ZFS acceptance flow:

```bash
OMARCHY_PATH="$HOME/src/omarchy" ./bin/omarchy-iso-test release/omarchy-*-local.iso --filesystem zfs --sync-omarchy "$HOME/src/omarchy"
```

Also run Btrfs encrypted and unencrypted regressions after shared installer changes.

## Required Acceptance Checks

- Root, home, `/tmp`, `/var/tmp`, and `/var/log` use the intended ZFS datasets.
- `/tmp` and `/var/tmp` report `FSTYPE=zfs`, never `tmpfs`.
- The pool is healthy and `bootfs` is correct after a second boot.
- The user home is encrypted and available only after password login.
- PAM unlock and delayed logout cleanup work from SDDM and console login.
- ArchZFS remains in `/etc/pacman.conf` after refresh/channel operations.
- Every installed kernel has a ZFS module and the UKI embeds hostid support.
- Snapper/Limine-Snapper and hibernation artifacts are absent on ZFS.
- Btrfs acceptance behavior remains unchanged.
