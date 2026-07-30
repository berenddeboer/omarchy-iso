"""Native ZFS storage preparation and validation for full-disk installs."""

from __future__ import annotations

import os
import shutil
import subprocess
import time
from pathlib import Path

from .context import InstallContext
from .ui import info


def _run(args: list[str], **kwargs) -> subprocess.CompletedProcess:
    return subprocess.run(args, check=True, **kwargs)


def _partition_path(disk: str, number: int) -> str:
    return f"{disk}p{number}" if disk[-1:].isdigit() else f"{disk}{number}"


def _value(args: list[str]) -> str:
    return _run(args, capture_output=True, text=True).stdout.strip()


def _pool_uses_only_disk(pool: str, disk: str) -> bool:
    status = _value(["zpool", "status", "-P", "-L", pool])
    devices = [line.strip().split()[0] for line in status.splitlines() if line.strip().startswith("/dev/")]
    if not devices:
        return False
    expected = str(Path(disk).resolve())
    for device in devices:
        parent = _value(["lsblk", "-ndo", "PKNAME", device])
        if not parent or str(Path("/dev") / parent) != expected:
            return False
    return True


def prepare(ctx: InstallContext) -> None:
    storage = ctx.storage
    disk = storage.get("disk")
    pool = storage.get("pool", "zroot")
    root_dataset = storage.get("root_dataset", f"{pool}/ROOT/default")
    home_prefix = storage.get("home_prefix", f"{pool}/data/home")
    home_dataset = storage.get("home_dataset", f"{home_prefix}/{ctx.username}")
    password = ctx.user_credentials.get("encryption_password", "")

    if not disk or not Path(disk).is_block_device():
        raise RuntimeError(f"ZFS install disk is missing or invalid: {disk!r}")
    if len(password) < 8:
        raise RuntimeError("ZFS encrypted home requires a password of at least 8 characters")

    esp_device = _partition_path(disk, 1)
    zfs_partition = _partition_path(disk, 2)

    info("› loading ZFS kernel module")
    _run(["modprobe", "zfs"])

    # A retry may leave the selected disk's old pool imported. Never destroy a
    # same-named pool from another disk.
    if subprocess.run(["zpool", "list", "-H", pool], check=False, capture_output=True).returncode == 0:
        if not _pool_uses_only_disk(pool, disk):
            raise RuntimeError(f"refusing to destroy unrelated imported pool named {pool}")
        _run(["zpool", "destroy", "-f", pool])
    elif Path(zfs_partition).is_block_device():
        imported = subprocess.run(
            ["zpool", "import", "-N", "-f", "-d", zfs_partition, pool],
            check=False, capture_output=True,
        )
        if imported.returncode == 0:
            _run(["zpool", "destroy", "-f", pool])

    info(f"› partitioning {disk} for ZFS")
    _run(["sgdisk", "--zap-all", disk])
    _run([
        "sgdisk",
        "--new=1:1MiB:+2GiB", "--typecode=1:EF00", "--change-name=1:EFI",
        "--new=2:0:0", "--typecode=2:BF00", f"--change-name=2:{pool}",
        disk,
    ])
    subprocess.run(["partprobe", disk], check=False, capture_output=True)
    subprocess.run(["udevadm", "settle"], check=False)
    for _ in range(10):
        if Path(esp_device).is_block_device() and Path(zfs_partition).is_block_device():
            break
        time.sleep(1)
        subprocess.run(["partprobe", disk], check=False, capture_output=True)
        subprocess.run(["udevadm", "settle"], check=False)
    else:
        raise RuntimeError(f"ZFS partitions did not appear: {esp_device}, {zfs_partition}")

    _run(["mkfs.fat", "-F32", "-n", "OMARCHY_EFI", esp_device])
    partuuid = _value(["blkid", "-s", "PARTUUID", "-o", "value", zfs_partition])
    vdev = f"/dev/disk/by-partuuid/{partuuid}"
    if not Path(vdev).exists():
        raise RuntimeError(f"persistent ZFS vdev path did not appear: {vdev}")

    info(f"› creating ZFS pool {pool}")
    _run([
        "zpool", "create", "-f",
        "-o", "ashift=12", "-o", "autotrim=on",
        "-O", "acltype=posixacl", "-O", "relatime=on", "-O", "xattr=sa",
        "-O", "dnodesize=auto", "-O", "normalization=formD",
        "-O", "mountpoint=none", "-O", "canmount=off", "-O", "devices=off",
        "-O", "compression=zstd", "-R", str(ctx.target), pool, vdev,
    ])
    ctx.state["zfs_prepared"] = True

    _run(["zfs", "create", "-o", "mountpoint=none", f"{pool}/ROOT"])
    _run(["zfs", "create", "-o", "mountpoint=/", "-o", "canmount=noauto", root_dataset])
    _run(["zfs", "mount", root_dataset])

    _run(["zfs", "create", "-o", "mountpoint=none", f"{pool}/data"])
    _run(["zfs", "create", "-o", "mountpoint=/home", home_prefix])

    key_path = ctx.state_dir / "zfs-home.key"
    try:
        key_path.write_text(password)
        key_path.chmod(0o600)
        _run([
            "zfs", "create", "-o", "encryption=on", "-o", "keyformat=passphrase",
            "-o", f"keylocation=file://{key_path}",
            "-o", f"mountpoint=/home/{ctx.username}", home_dataset,
        ])
        _run(["zfs", "set", "keylocation=prompt", home_dataset])
    finally:
        key_path.unlink(missing_ok=True)

    datasets = [
        (f"{pool}/data/root", ["mountpoint=/root"]),
        (f"{pool}/data/srv", ["mountpoint=/srv"]),
        # /tmp is deliberately disk-backed, matching the development machine.
        (f"{pool}/data/tmp", ["mountpoint=/tmp"]),
        (f"{pool}/var", ["mountpoint=/var", "canmount=off"]),
        (f"{pool}/var/log", []),
        (f"{pool}/var/log/journal", ["acltype=posixacl"]),
        (f"{pool}/var/cache", []),
        (f"{pool}/var/tmp", []),
        (f"{pool}/var/lib", ["mountpoint=/var/lib", "canmount=off"]),
        (f"{pool}/var/lib/docker", []),
        (f"{pool}/var/lib/libvirt", []),
        (f"{pool}/var/lib/machines", []),
    ]
    for dataset, properties in datasets:
        command = ["zfs", "create"]
        for prop in properties:
            command.extend(["-o", prop])
        command.append(dataset)
        _run(command)

    _run(["zpool", "set", f"bootfs={root_dataset}", pool])
    _run(["zpool", "set", "cachefile=/etc/zfs/zpool.cache", pool])

    esp_mount = ctx.target / "boot"
    esp_mount.mkdir(parents=True, exist_ok=True)
    _run(["mount", esp_device, str(esp_mount)])
    (ctx.target / "etc/zfs").mkdir(parents=True, exist_ok=True)
    shutil.copy2("/etc/zfs/zpool.cache", ctx.target / "etc/zfs/zpool.cache")
    for path in (ctx.target / "tmp", ctx.target / "var/tmp"):
        path.mkdir(parents=True, exist_ok=True)
        path.chmod(0o1777)

    storage.update({
        "esp_device": esp_device,
        "zfs_device": vdev,
        "root_dataset": root_dataset,
        "home_prefix": home_prefix,
        "home_dataset": home_dataset,
    })

    validate_mounts(ctx)


def validate_mounts(ctx: InstallContext) -> None:
    pool = ctx.storage.get("pool", "zroot")
    expected = {
        ctx.target: f"{pool}/ROOT/default",
        ctx.target / "home": f"{pool}/data/home",
        ctx.target / "home" / ctx.username: f"{pool}/data/home/{ctx.username}",
        ctx.target / "tmp": f"{pool}/data/tmp",
        ctx.target / "var/tmp": f"{pool}/var/tmp",
        ctx.target / "var/log": f"{pool}/var/log",
    }
    for mountpoint, source in expected.items():
        actual = _value(["findmnt", "-n", "-o", "SOURCE", "--mountpoint", str(mountpoint)])
        if actual != source:
            raise RuntimeError(f"expected {mountpoint} from {source}, got {actual or 'nothing'}")
        fstype = _value(["findmnt", "-n", "-o", "FSTYPE", "--mountpoint", str(mountpoint)])
        if fstype != "zfs":
            raise RuntimeError(f"expected {mountpoint} to be ZFS, got {fstype or 'nothing'}")


def validate_target(ctx: InstallContext, limine_text: str) -> None:
    validate_mounts(ctx)
    pool = ctx.storage.get("pool", "zroot")
    root_dataset = ctx.storage["root_dataset"]
    home_dataset = ctx.storage["home_dataset"]

    if _value(["zpool", "status", "-x", pool]) != f"pool '{pool}' is healthy":
        raise RuntimeError(f"ZFS pool {pool} is not healthy")
    if _value(["zpool", "get", "-H", "-o", "value", "bootfs", pool]) != root_dataset:
        raise RuntimeError(f"ZFS pool {pool} has the wrong bootfs")

    required_properties = {
        "encryption": "aes-256-gcm",
        "keyformat": "passphrase",
        "keylocation": "prompt",
        "keystatus": "available",
    }
    for prop, expected in required_properties.items():
        actual = _value(["zfs", "get", "-H", "-o", "value", prop, home_dataset])
        if actual != expected:
            raise RuntimeError(f"{home_dataset} {prop} is {actual!r}, expected {expected!r}")

    if f"root=ZFS={root_dataset}" not in limine_text or "zfs_boot_only=1" not in limine_text:
        raise RuntimeError("Limine config is missing the ZFS root command line")

    fstab = (ctx.target / "etc/fstab").read_text()
    records = [line.split() for line in fstab.splitlines() if line.strip() and not line.lstrip().startswith("#")]
    if len(records) != 1 or len(records[0]) < 3 or records[0][2] != "vfat":
        raise RuntimeError("ZFS fstab must contain only the ESP mount")

    required = [
        ctx.target / "etc/hostid",
        ctx.target / "etc/zfs/zpool.cache",
        ctx.target / "etc/pam.d/zfs-key",
        ctx.target / "usr/lib/security/pam_zfs_key.so",
        ctx.target / "usr/local/lib/omarchy/zfs-pam-unlock-home",
        ctx.target / f"home/{ctx.username}/.config/omarchy/shell.json",
    ]
    for path in required:
        if not path.exists() or path.stat().st_size == 0:
            raise RuntimeError(f"required ZFS target file missing or empty: {path}")

    hooks = (ctx.target / "etc/mkinitcpio.conf.d/omarchy_hooks.conf").read_text()
    if " zfs filesystems" not in hooks or "fsck" in hooks or "btrfs-overlayfs" in hooks:
        raise RuntimeError("mkinitcpio hooks are not configured for ZFS")
    if "/etc/hostid" not in (ctx.target / "etc/mkinitcpio.conf.d/zfs_hostid.conf").read_text():
        raise RuntimeError("mkinitcpio does not include /etc/hostid")

    tmp_mask = ctx.target / "etc/systemd/system/tmp.mount"
    if not tmp_mask.is_symlink() or os.readlink(tmp_mask) != "/dev/null":
        raise RuntimeError("tmp.mount is not masked; /tmp could be moved into RAM")

    for unit in ("zfs-import-cache.service", "zfs-import.target", "zfs-mount.service", "zfs.target"):
        result = subprocess.run(
            ["arch-chroot", str(ctx.target), "systemctl", "is-enabled", unit],
            capture_output=True, text=True,
        )
        if result.returncode != 0:
            raise RuntimeError(f"{unit} is not enabled")

    for package in ("zfs-utils", "zfs-dkms", "dkms"):
        _run(["arch-chroot", str(ctx.target), "pacman", "-Q", package], capture_output=True)

    for modules_dir in sorted((ctx.target / "usr/lib/modules").iterdir()):
        if not modules_dir.is_dir():
            continue
        result = subprocess.run(
            ["arch-chroot", str(ctx.target), "modinfo", "-k", modules_dir.name, "zfs"],
            capture_output=True,
        )
        if result.returncode != 0:
            raise RuntimeError(f"ZFS module missing for kernel {modules_dir.name}")

    if (ctx.target / "etc/mkinitcpio.conf.d/omarchy_resume.conf").exists():
        raise RuntimeError("ZFS install unexpectedly has hibernation resume configuration")
    if (ctx.target / "etc/sddm.conf.d/autologin.conf").exists():
        raise RuntimeError("ZFS encrypted home requires password login, not SDDM autologin")


def cleanup(ctx: InstallContext) -> None:
    if not ctx.state.get("zfs_prepared"):
        return
    pool = ctx.storage.get("pool", "zroot")
    subprocess.run(["umount", "-R", str(ctx.target)], check=False, capture_output=True)
    subprocess.run(["zpool", "export", "-f", pool], check=False, capture_output=True)
