# Omarchy 3 ZFS to Quattro Upgrade

## Goal

Provide a tested, recoverable in-place upgrade from an existing Omarchy 3 system on ZFS to the paired `quattro-on-zfs` Omarchy and ISO implementation.

The fresh-install path is already validated. This plan covers only migration of an existing machine.

## Safety Requirements

- [ ] Do not run the migration on the real machine until it passes against a clone of that machine.
- [ ] Record the current pool, dataset, mountpoint, encryption, kernel, boot, PAM, package, and Omarchy state.
- [ ] Create matching pre-upgrade snapshots of the root and encrypted user-home datasets.
- [ ] Export a list of installed native and foreign packages.
- [ ] Back up `/boot`, `/etc`, the pacman keyring, and the current Omarchy checkout separately from ZFS snapshots.
- [ ] Confirm external recovery media can import `zroot`, load the encrypted home key, mount all datasets, and repair Limine.
- [ ] Define and test rollback before attempting the upgrade.
- [ ] Keep the existing bootable UKI and Limine entry until the upgraded system has booted successfully twice.

## Inventory The Existing System

- [ ] Record `zpool status`, `zpool get all zroot`, and `zfs get all` for relevant datasets.
- [ ] Confirm the exact root, home, `/tmp`, `/var/tmp`, `/var/log`, package-cache, Docker, and libvirt datasets.
- [ ] Confirm `/tmp` is disk-backed ZFS and not tmpfs.
- [ ] Record the current `/etc/hostid` and verify it is embedded in the working UKI.
- [ ] Record installed kernels, headers, ZFS packages, DKMS status, and modules.
- [ ] Save `/etc/mkinitcpio.conf` and all `/etc/mkinitcpio.conf.d/*` files.
- [ ] Save `/etc/default/limine`, `/boot/limine.conf`, `/etc/kernel/cmdline`, and EFI boot entries.
- [ ] Save `/etc/pam.d`, ZFS PAM helpers, SDDM configuration, and enabled ZFS services.
- [ ] Save `/etc/pacman.conf`, mirror configuration, custom repositories, and signing keys.
- [ ] Identify the current Omarchy source path, branch, commit, migrations, user configuration, and locally modified files.
- [ ] Identify configuration formats that changed between Omarchy 3 and Quattro, especially Hyprland and shell configuration.

## Build The Upgrade Mechanism

- [ ] Add a dedicated, explicit upgrade command to the `omarchy/quattro-on-zfs` branch.
- [ ] Refuse to run unless `/` is ZFS and the expected pool/dataset layout is recognized.
- [ ] Refuse to run when required snapshots, free space, hostid, ESP mounts, or recovery files are missing.
- [ ] Support a dry-run mode that reports every package, file, service, PAM, and boot change.
- [ ] Make each migration step idempotent and safe to rerun after interruption.
- [ ] Write a persistent migration log outside `/tmp`.
- [ ] Add checkpoints so a failed step can be resumed without replaying destructive work.

## Convert To Quattro Packages

- [ ] Build Quattro-on-ZFS `omarchy-dev` and `omarchy-settings-dev` packages from the paired branch.
- [ ] Verify package contents include all ZFS setup and PAM helper files.
- [ ] Transition from the Omarchy 3 source-tree installation to Quattro's package-backed `/usr/share/omarchy` layout.
- [ ] Preserve the old source checkout as a recovery artifact rather than deleting it immediately.
- [ ] Install Quattro packages without allowing package hooks to rebuild a partially configured UKI.
- [ ] Ensure the ArchZFS signing key is installed and locally trusted before enabling the online repository.
- [ ] Preserve `[archzfs]` through pacman refreshes and channel changes.
- [ ] Synchronize package databases and verify an update can resolve ZFS packages before reboot.

## Migrate Persistent ZFS Configuration

- [ ] Preserve the existing pool GUID, vdev paths, dataset properties, encryption roots, and key locations.
- [ ] Do not recreate or rename existing datasets during the upgrade.
- [ ] Verify `bootfs=zroot/ROOT/default` and refresh `/etc/zfs/zpool.cache`.
- [ ] Preserve the existing hostid unless there is a proven reason to regenerate it.
- [ ] Install Quattro ZFS mkinitcpio hooks with `zfs filesystems` and without `fsck` or `btrfs-overlayfs`.
- [ ] Ensure `/etc/hostid` is included in every generated initramfs and UKI.
- [ ] Keep hibernation and Btrfs swapfile setup disabled.
- [ ] Disable Snapper and `limine-snapper-sync` services on ZFS.
- [ ] Preserve native ZFS snapshot behavior and document that boot-menu restore remains unsupported.
- [ ] Mask `tmp.mount` and verify `/tmp` remains mounted from `zroot/data/tmp`.

## Migrate Login And Encrypted Homes

- [ ] Preserve every existing encrypted user-home dataset and its encryption root.
- [ ] Verify each login password still unlocks the matching dataset before changing PAM.
- [ ] Install the Quattro ZFS PAM helpers and service-scoped PAM stack.
- [ ] Ensure login fails closed when a known encrypted home is not mounted.
- [ ] Ensure users without a ZFS home dataset are not accidentally locked out.
- [ ] Verify password changes update the ZFS dataset key.
- [ ] Verify SDDM, console login, `su -`, SSH policy, screen unlock, logout cleanup, and key unloading.
- [ ] Keep SDDM autologin disabled and preserve the selected Omarchy session.

## Migrate User Configuration

- [ ] Run Quattro migrations against a copy of the real home dataset first.
- [ ] Preserve user-edited configuration rather than replacing the whole home with `/etc/skel`.
- [ ] Seed only files required by Quattro that do not already exist.
- [ ] Migrate Hyprland configuration to the Quattro format without losing local monitor, input, binding, and appearance settings.
- [ ] Ensure `~/.config/omarchy/shell.json` exists and is valid.
- [ ] Preserve themes, backgrounds, application data, development tools, SSH configuration, and secrets.
- [ ] Verify `OMARCHY_PATH` resolves to the package-backed path after migration.
- [ ] Mark only successfully applied Quattro migrations as complete.

## Boot Migration

- [ ] Generate a new Quattro UKI alongside the known-working Omarchy 3 UKI.
- [ ] Use `root=ZFS=zroot/ROOT/default` and retain `zfs_boot_only=1`.
- [ ] Verify the ZFS module is built for every installed kernel before generating UKIs.
- [ ] Inspect the new UKI for `/etc/hostid`, ZFS hooks, kernel command line, and required modules.
- [ ] Add a separate temporary Limine entry for the upgraded system.
- [ ] Preserve the old default entry until two successful upgraded boots.
- [ ] Preserve EFI boot order and fallback boot files.

## Automated Testing

- [x] Create a VM image representing an Omarchy 3 ZFS installation, not a fresh Quattro install.
- [x] Populate it with representative user configuration and locally modified files.
- [ ] Test dry-run output without changing the VM.
- [ ] Test a successful upgrade and two consecutive boots.
- [ ] Test interruption and rerun at every migration checkpoint.
- [ ] Test rollback after package installation, PAM changes, UKI generation, and first boot.
- [x] Test wrong-password and locked-home behavior.
- [x] Test password changes followed by logout and login.
- [ ] Test pacman refresh, channel changes, and a normal `omarchy-update` after migration.
- [ ] Run the standard Quattro acceptance suite with `OMARCHY_EXPECTED_FILESYSTEM=zfs`.
- [ ] Verify no failed system or user units.
- [ ] Verify shutdown and reboot do not leave the pool dirty or produce unexpected ZFS import errors.

### VM Test Result (2026-08-03)

The immutable Omarchy 3 ZFS fixture upgraded far enough to boot Quattro repeatedly with a healthy pool, the package-backed Omarchy layout, the expected ZFS kernel module, disk-backed `/tmp` and `/var/tmp`, and password-gated encrypted home mounting. Wrong-password rejection and password/ZFS-key rotation passed. The original fixture and its OVMF state remained byte-for-byte unchanged.

Real-machine rollout remains blocked. Package hooks generated a UKI during the package transaction despite the initial deferral attempt, headless migration resume still needs a proper credential/session mechanism, dual-UKI preservation was completed manually rather than by a checkpointed command, native ZFS rollback has not been exercised from recovery media, and every tested shutdown reports failed unmounts for `zroot/var/log` and `zroot/var/log/journal`.

## Real-Machine Rollout

- [ ] Boot recovery media and confirm the documented rollback procedure immediately before migration.
- [ ] Disconnect unnecessary external pools to avoid pool-name or device-selection mistakes.
- [ ] Run the migration from a local console with stable power and network access.
- [ ] Save the complete migration log externally.
- [ ] Boot the temporary Quattro entry while retaining the Omarchy 3 entry.
- [ ] Validate networking, graphics, audio, suspend, login, screen unlock, encrypted home, Docker, and development workloads.
- [ ] Reboot a second time and repeat storage, login, and service checks.
- [ ] Only then make the Quattro entry the default.
- [ ] Retain rollback snapshots and the old UKI until the upgraded system has been used successfully for an agreed period.

## Completion Criteria

- [ ] The migration is automated, idempotent, and covered by an Omarchy 3 ZFS fixture.
- [ ] Dry-run, interrupted-run, rollback, and successful-run scenarios pass.
- [ ] The real system boots twice with a healthy pool and encrypted home mounted only after authentication.
- [ ] `/tmp` and `/var/tmp` remain disk-backed ZFS datasets.
- [ ] Omarchy updates and pacman refreshes preserve ZFS support.
- [ ] The old boot path and rollback data are removed only by a separate explicit cleanup step.
