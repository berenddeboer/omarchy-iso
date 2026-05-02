# Omarchy ISO

The Omarchy ISO streamlines [the installation of Omarchy](https://learn.omacom.io/2/the-omarchy-manual/50/getting-started). It includes the Omarchy Configurator as a front-end to archinstall and automatically launches the [Omarchy Installer](https://github.com/basecamp/omarchy) after base arch has been setup.

## Downloading the latest ISO

See the ISO link on [omarchy.org](https://omarchy.org).

## Creating the ISO

Run `./bin/omarchy-iso-make` and the output goes into `./release`. You can build from your local `$OMARCHY_PATH` for testing by using `--local-source` or from a checkout of the dev branch (instead of master) by using `--dev`.

### Environment Variables

You can customize the repositories used during the build process by passing in variables:

- `OMARCHY_INSTALLER_REPO` - GitHub repository for the installer (default: `basecamp/omarchy`)
- `OMARCHY_INSTALLER_REF` - Git ref (branch/tag) for the installer (default: `master`)

Example usage:
```bash
OMARCHY_INSTALLER_REPO="myuser/omarchy-fork" OMARCHY_INSTALLER_REF="some-feature" ./bin/omarchy-iso-make
```

## Testing the ISO

Run `./bin/omarchy-iso-boot [release/omarchy.iso]` for a manual smoke test. Without an ISO argument it uses `gum` to choose an ISO and ask whether to reuse the disk.

For an automated local VM install test that still exposes the full interactive display, run `./bin/omarchy-iso-vm-test`. It builds from `~/src/omarchy`, boots the ISO in a KVM/QEMU VM with VNC on `127.0.0.1:5905`, drives the visible installer prompts, and saves serial logs, tty screenshots, and screen text under `release/vm-test/current`. This runner does not use `gum` on the host side.

While the VM is running, you can send keys or capture the display from another terminal:

```bash
./bin/omarchy-iso-vm-test key ret
./bin/omarchy-iso-vm-test screenshot
./bin/omarchy-iso-vm-test screen
```

## Signing the ISO

Run `./bin/omarchy-iso-sign [gpg-user] [release/omarchy.iso]`.

## Uploading the ISO

Run `./bin/omarchy-iso-upload [release/omarchy.iso]`. This requires you've configured rclone (use `rclone config`).

## Full release of the ISO

Run `./bin/omarchy-iso-release VERSION` to create, test, sign, and upload the ISO in one flow. Add `--rc` to release an RC build instead.
