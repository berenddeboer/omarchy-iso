# ZFS Progress

## This Project

This workstream is the Omarchy 3 ZFS to Quattro **upgrade**.

It is not the Quattro-on-ZFS installer ISO. Building a fresh Omarchy/Quattro ZFS ISO is a later, separate project. Do not mix that work into this upgrade path.

## Sequence

1. Build one Omarchy 3 ZFS ISO and keep it as a reusable reference.
2. Boot that ISO and test the Omarchy 3 ZFS install.
3. Run `omarchy-upgrade-to-quattro` against that existing ZFS system.
4. Only after the upgrade path is solid, start the separate Quattro-on-ZFS ISO project.

## Current Status

The Omarchy 3 ZFS ISO is kept, and the installed disk is the gold master. That gold disk must stay on Omarchy 3. Every upgrade test uses a disposable copy.

The ISO comes from `feat/omarchy-zfs-iso` plus the paired Omarchy 3 source on `feat/omarchy-on-zfs`. Keep the finished image at:

```text
test-runs/omarchy3-zfs-iso/omarchy-3-zfs.iso
```

Do not rebuild that ISO unless the reference is missing or proven invalid. Later Quattro ISO builds in `release/` must not overwrite it.

The installed gold master is:

```text
test-runs/omarchy3-zfs-gold/omarchy3-zfs.qcow2
```

Never boot or upgrade that disk. Never pass it to QEMU as a writable drive. Create a copy for every test:

```bash
./bin/omarchy-iso-clone-omarchy3-zfs
./bin/omarchy-iso-clone-omarchy3-zfs --boot
```

The original install disk `test-runs/omarchy3-zfs-iso/boot.qcow2` is also made read-only after the freeze.

Upgrade details remain in [plans/omarchy-3-zfs-to-quattro.md](plans/omarchy-3-zfs-to-quattro.md). Disposable VM artifacts stay under the ignored `test-runs/` tree.

## Current Phase: Omarchy 3 ZFS ISO

- [x] Build the Omarchy 3 ZFS ISO from `feat/omarchy-zfs-iso` + `feat/omarchy-on-zfs`.
- [x] Copy it to `test-runs/omarchy3-zfs-iso/` with a build manifest.
- [x] Boot the reference ISO for a manual install/test.
- [x] Keep the ISO as the starting point for later Quattro upgrade runs.

## Next Phase: Quattro Upgrade Against Existing ZFS

Use a clone. Do not upgrade the gold master.

- [x] Install Omarchy 3 on ZFS from the kept ISO.
- [x] Freeze `test-runs/omarchy3-zfs-gold/` as a read-only Omarchy 3 gold master.
- [x] Run `omarchy-upgrade-to-quattro` against a disposable copy, never the gold disk.
- [ ] Preserve the old UKI and add a temporary Quattro boot entry.
- [ ] Verify pool health, encrypted home unlock, disk-backed `/tmp` and `/var/tmp`, and a matching ZFS kernel module.
- [ ] Then continue the remaining upgrade blockers in the prior VM notes below.

## Later Project: Quattro-on-ZFS ISO

Out of scope until the upgrade path is done.

- Fresh Quattro install with ZFS root and encrypted ZFS home.
- `quattro-on-zfs` ISO + Omarchy branches.
- Acceptance of a new Quattro-on-ZFS machine, not an Omarchy 3 migration.

## Prior VM Notes

Earlier disposable-VM work already proved a lot of the upgrade internals, but it is not a substitute for booting the kept Omarchy 3 ZFS ISO and then running Quattro against that install.

- [x] Build a sanitized, immutable Omarchy 3 ZFS fixture.
- [x] Verify the fixture disk and OVMF state remain byte-for-byte unchanged.
- [x] Build `omarchy-dev` and `omarchy-settings-dev` from the paired `quattro-on-zfs` source.
- [x] Upgrade a disposable qcow2 overlay to the package-backed `/usr/share/omarchy` layout.
- [x] Boot the Quattro UKI repeatedly with a healthy `zroot` pool.
- [x] Verify the installed kernel has a matching ZFS module.
- [x] Verify `/tmp` and `/var/tmp` are disk-backed ZFS datasets.
- [x] Verify PAM password login unlocks `zroot/data/home/omarchy`.
- [x] Verify a wrong password fails.
- [x] Verify a password change also changes the ZFS key: the old password fails and the new password unlocks the home.
- [x] Preserve and hash-check the known-working Omarchy 3 UKI alongside the Quattro UKI.
- [x] Verify no failed system units during the post-upgrade console validation.
- [x] Exercise interruption and rerun after the first package attempt stopped safely.

### Remaining upgrade blockers

- [ ] Prevent every intermediate UKI rebuild during package transactions.
- [ ] Move old-UKI preservation and dual-entry Limine generation into the migration command.
- [ ] Keep the Omarchy 3 entry as the default while allowing a temporary Quattro entry for test boots.
- [ ] Add persistent migration checkpoints and a resume command.
- [ ] Add a persistent migration log and copy it to the external recovery destination.
- [ ] Integrate inventory, `/boot`, `/etc`, pacman keyring, package lists, and legacy Omarchy checkout backups into the migration command.
- [ ] Install and locally trust the verified ArchZFS signing key before repository synchronization.
- [ ] Handle a missing `zroot/data/tmp` explicitly.
- [ ] Make headless/user migration resume work without temporary passwordless sudo.
- [ ] Finish all pending migrations from a real graphical Quattro session.
- [ ] Run the standard Quattro graphical acceptance suite with `OMARCHY_EXPECTED_FILESYSTEM=zfs`.
- [ ] Verify failed user units after a graphical login, not only system units from the console.
- [ ] Fix or formally account for failed shutdown unmounts of `zroot/var/log` and `zroot/var/log/journal`.
- [ ] Verify clean pool export/import across shutdown and reboot after the log-dataset issue is fixed.
- [ ] Test native ZFS rollback from recovery media.
- [ ] Test interruption and resume at every destructive checkpoint.
- [ ] Test SDDM login, screen unlock, `su -`, SSH policy, logout cleanup, and key unloading in the upgraded graphical system.
- [ ] Test pacman refresh, channel changes, and a normal `omarchy-update` while preserving `[archzfs]` and the ZFS packages.
- [ ] Re-run two complete Quattro boots after all fixes, with both UKIs and both Limine entries still present.
- [ ] Rehearse the real-machine recovery media flow.

## Real Machine Gate

Do not run the migration on the real machine until the kept Omarchy 3 ZFS ISO has been used as the starting point, the Quattro upgrade against that existing ZFS install has passed, recovery media has been rehearsed, native rollback has passed, and the upgraded VM has completed two clean boots and shutdowns without unexpected ZFS errors.
