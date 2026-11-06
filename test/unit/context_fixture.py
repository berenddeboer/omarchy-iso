"""Partial installer contexts with the real filesystem/encryption properties."""

from types import SimpleNamespace

from orchestrator.context import InstallContext


class ContextFixture(SimpleNamespace):
    storage = {}
    encrypt = False
    filesystem = InstallContext.filesystem
    is_zfs = InstallContext.is_zfs
    has_luks_root = InstallContext.has_luks_root
    boot_requires_passphrase = InstallContext.boot_requires_passphrase
