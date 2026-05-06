#!/usr/bin/env bash
set -euo pipefail

use_omarchy_helpers() {
  export OMARCHY_PATH="/root/omarchy"
  export OMARCHY_INSTALL="/root/omarchy/install"
  export OMARCHY_INSTALL_LOG_FILE="/var/log/omarchy-install.log"
  export OMARCHY_MIRROR="$(cat /root/omarchy_mirror)"
  source /root/omarchy/install/helpers/all.sh
}

run_configurator() {
  set_tokyo_night_colors
  ./configurator
  export OMARCHY_USER="$(jq -r '.users[0].username' user_credentials.json)"
}

install_arch() {
  clear_logo
  gum style --foreground 3 --padding "1 0 0 $PADDING_LEFT" "Installing..."
  echo

  touch /var/log/omarchy-install.log

  start_log_output

  # Set CURRENT_SCRIPT for the trap to display better when nothing is returned for some reason
  CURRENT_SCRIPT="install_base_system"
  if [[ $(<root_filesystem.txt) == "zfs" ]]; then
    install_zfs_base_system > >(sed -u 's/\x1b\[[0-9;]*[a-zA-Z]//g' >>/var/log/omarchy-install.log) 2>&1
  else
    install_base_system > >(sed -u 's/\x1b\[[0-9;]*[a-zA-Z]//g' >>/var/log/omarchy-install.log) 2>&1
  fi
  unset CURRENT_SCRIPT
  stop_log_output
}

install_omarchy() {
  ensure_zfs_target_mounts_if_needed "before installing gum"
  assert_zfs_chroot_home_mount_if_needed "before installing gum"
  chroot_bash -lc "sudo pacman -S --noconfirm --needed gum" >/dev/null
  ensure_zfs_target_mounts_if_needed "after installing gum"
  assert_zfs_chroot_home_mount_if_needed "after installing gum"
  assert_zfs_chroot_home_mount_if_needed "before Omarchy install"
  chroot_bash -lc "source /home/$OMARCHY_USER/.local/share/omarchy/install.sh || bash"
  ensure_zfs_target_mounts_if_needed "after Omarchy install"
  assert_zfs_chroot_home_mount_if_needed "after Omarchy install"

  if [[ $(<root_filesystem.txt) == "zfs" ]]; then
    configure_zfs_sddm_password_login
    append_archzfs_repo /mnt/etc/pacman.conf
  fi

  verify_omarchy_target_config
  cleanup_zfs_home_probe_if_needed

  # Reboot if requested by installer
  if [[ -f /mnt/var/tmp/omarchy-install-completed ]]; then
    reboot
  fi
}

ensure_zfs_target_mounts_if_needed() {
  if [[ $(<root_filesystem.txt) == "zfs" ]]; then
    ensure_zfs_target_mounts zroot "${1:-unspecified}"
  fi
}

verify_omarchy_target_config() {
  local user_home="/mnt/home/$OMARCHY_USER"

  if ! omarchy_home_has_target_config "$user_home"; then
    echo "Expected Omarchy config in $user_home" >&2
    exit 1
  fi

  if [[ $(<root_filesystem.txt) == "zfs" && ! -f /mnt/var/log/omarchy-install.log ]]; then
    echo "Expected Omarchy install log in /mnt/var/log/omarchy-install.log" >&2
    exit 1
  fi
}

omarchy_home_has_target_config() {
  local user_home="$1"
  local hypr_config="$user_home/.config/hypr/hyprland.conf"

  if [[ ! -f $user_home/.local/share/omarchy/install.sh ]]; then
    return 1
  fi
  if [[ ! -f $hypr_config ]]; then
    return 1
  fi
  if ! grep -q 'source = ~/.local/share/omarchy/default/hypr/autostart.conf' "$hypr_config"; then
    return 1
  fi
}

zfs_home_probe_name() {
  printf '.omarchy-zfs-home-probe'
}

zfs_user_home_dataset() {
  printf 'zroot/data/home/%s' "$OMARCHY_USER"
}

prepare_zfs_home_probe() {
  local user_ids probe_path

  user_ids=$(awk -F: -v user="$OMARCHY_USER" '$1 == user { print $3 ":" $4 }' /mnt/etc/passwd)
  if [[ -z $user_ids ]]; then
    echo "Expected target user $OMARCHY_USER in /mnt/etc/passwd" >&2
    exit 1
  fi

  install -d -m 700 -o "${user_ids%:*}" -g "${user_ids#*:}" "/mnt/home/$OMARCHY_USER"
  probe_path="/mnt/home/$OMARCHY_USER/$(zfs_home_probe_name)"
  zfs_user_home_dataset >"$probe_path"
  chown "$user_ids" "$probe_path"
}

cleanup_zfs_home_probe_if_needed() {
  if [[ $(<root_filesystem.txt) == "zfs" ]]; then
    rm -f "/mnt/home/$OMARCHY_USER/$(zfs_home_probe_name)"
  fi
}

assert_zfs_chroot_home_mount_if_needed() {
  if [[ $(<root_filesystem.txt) == "zfs" ]]; then
    assert_zfs_chroot_home_mount "${1:-unspecified}"
  fi
}

assert_zfs_chroot_home_mount() {
  local context="$1"
  local probe_name

  prepare_zfs_home_probe
  probe_name=$(zfs_home_probe_name)

  chroot_bash -lc "context='$context'; expected='$(zfs_user_home_dataset)'; probe=\"\$HOME/$probe_name\"; root_source=\$(findmnt -n -o SOURCE --mountpoint / 2>/dev/null || true); printf 'ZFS chroot home path check (%s): / source=%s, HOME=%s, probe=%s\\n' \"\$context\" \"\$root_source\" \"\$HOME\" \"\$probe\" >&2; if [[ ! -f \$probe ]] || [[ \$(<\"\$probe\") != \$expected ]]; then echo \"Expected chroot HOME to resolve to \$expected during \$context\" >&2; findmnt -R / >&2 || true; ls -la /home /home/$OMARCHY_USER >&2 || true; exit 1; fi"
}

# Set Tokyo Night color scheme for the terminal
set_tokyo_night_colors() {
  if [[ $(tty) == "/dev/tty"* ]]; then
    # Tokyo Night color palette
    echo -en "\e]P01a1b26" # black (background)
    echo -en "\e]P1f7768e" # red
    echo -en "\e]P29ece6a" # green
    echo -en "\e]P3e0af68" # yellow
    echo -en "\e]P47aa2f7" # blue
    echo -en "\e]P5bb9af7" # magenta
    echo -en "\e]P67dcfff" # cyan
    echo -en "\e]P7a9b1d6" # white
    echo -en "\e]P8414868" # bright black
    echo -en "\e]P9f7768e" # bright red
    echo -en "\e]PA9ece6a" # bright green
    echo -en "\e]PBe0af68" # bright yellow
    echo -en "\e]PC7aa2f7" # bright blue
    echo -en "\e]PDbb9af7" # bright magenta
    echo -en "\e]PE7dcfff" # bright cyan
    echo -en "\e]PFc0caf5" # bright white (foreground)

    # Set default foreground and background
    echo -en "\033[0m"
    clear
  fi
}

install_base_system() {
  # Initialize and populate the keyring
  pacman-key --init
  pacman-key --populate archlinux
  pacman-key --populate omarchy

  # Sync the offline database so pacman can find packages
  pacman -Sy --noconfirm

  # Ensure that no mounts exist from past install attempts
  findmnt -R /mnt >/dev/null && umount -R /mnt

  # Workarounds for archinstall 4.2 regressions under Python 3.14:
  # 1. sync_log_to_install_medium: `self.target / absolute_logfile` drops
  #    self.target because the RHS is absolute, so Path.copy() raises EINVAL
  #    (source == target).
  # 2. _add_limine_bootloader: `Path.copy(efi_dir_path)` raises IsADirectoryError
  #    because 3.14's Path.copy treats target as a literal path, not a directory
  #    (shutil.copy used to auto-append the source filename).
  sed -i \
    -e 's|logfile_target = self\.target / absolute_logfile$|logfile_target = self.target / absolute_logfile.relative_to("/")|' \
    -e 's|(limine_path / file)\.copy(efi_dir_path)|(limine_path / file).copy(efi_dir_path / file)|' \
    -e "s|(limine_path / 'limine-bios.sys')\.copy(boot_limine_path)|(limine_path / 'limine-bios.sys').copy(boot_limine_path / 'limine-bios.sys')|" \
    /usr/lib/python3.14/site-packages/archinstall/lib/installer.py

  # Install using files generated by the ./configurator
  # Skip NTP and WKD sync since we're offline (keyring is pre-populated in ISO)
  archinstall \
    --config user_configuration.json \
    --creds user_credentials.json \
    --silent \
    --skip-ntp \
    --skip-wkd \
    --skip-wifi-check

  prepare_target_for_omarchy
}

prepare_target_for_omarchy() {
  ensure_zfs_target_mounts_if_needed "before preparing target for Omarchy"
  assert_zfs_chroot_home_mount_if_needed "before preparing target for Omarchy"

  # After the base system is installed but before our installer runs,
  # we need to ensure the offline pacman.conf is in place.
  cp /etc/pacman.conf /mnt/etc/pacman.conf

  # Mount the offline mirror so it's accessible in the chroot
  mkdir -p /mnt/var/cache/omarchy/mirror/offline
  mount --bind /var/cache/omarchy/mirror/offline /mnt/var/cache/omarchy/mirror/offline

  # Mount the packages dir so it's accessible in the chroot
  mkdir -p /mnt/opt/packages
  mount --bind /opt/packages /mnt/opt/packages
  ensure_zfs_target_mounts_if_needed "after bind mounting installer resources"
  assert_zfs_chroot_home_mount_if_needed "after bind mounting installer resources"

  # No need to ask for sudo during the installation (omarchy itself responsible for removing after install)
  mkdir -p /mnt/etc/sudoers.d
  cat >/mnt/etc/sudoers.d/99-omarchy-installer <<EOF
root ALL=(ALL:ALL) NOPASSWD: ALL
%wheel ALL=(ALL:ALL) NOPASSWD: ALL
$OMARCHY_USER ALL=(ALL:ALL) NOPASSWD: ALL
EOF
  chmod 440 /mnt/etc/sudoers.d/99-omarchy-installer

  # Copy the local omarchy repo to the user's home directory
  ensure_zfs_target_mounts_if_needed "before copying Omarchy source"
  mkdir -p /mnt/home/$OMARCHY_USER/.local/share/
  cp -r /root/omarchy /mnt/home/$OMARCHY_USER/.local/share/
  ensure_zfs_target_mounts_if_needed "after copying Omarchy source"
  assert_zfs_chroot_home_mount_if_needed "after copying Omarchy source"

  chown -R 1000:1000 /mnt/home/$OMARCHY_USER/.local/

  # Ensure all necessary scripts are executable
  find /mnt/home/$OMARCHY_USER/.local/share/omarchy -type f -path "*/bin/*" -exec chmod +x {} \;
  chmod +x /mnt/home/$OMARCHY_USER/.local/share/omarchy/boot.sh 2>/dev/null || true
  chmod +x /mnt/home/$OMARCHY_USER/.local/share/omarchy/default/waybar/indicators/screen-recording.sh 2>/dev/null || true
  chmod +x /mnt/home/$OMARCHY_USER/.local/share/omarchy/default/waybar/indicators/idle.sh 2>/dev/null || true
  chmod +x /mnt/home/$OMARCHY_USER/.local/share/omarchy/default/waybar/indicators/notification-silencing.sh 2>/dev/null || true

  if [[ ! -f /mnt/home/$OMARCHY_USER/.local/share/omarchy/install.sh ]]; then
    echo "Expected Omarchy source in /mnt/home/$OMARCHY_USER/.local/share/omarchy" >&2
    exit 1
  fi
}

partition_path() {
  if [[ $1 =~ [0-9]$ ]]; then
    printf '%sp%s' "$1" "$2"
  else
    printf '%s%s' "$1" "$2"
  fi
}

kernel_headers_for() {
  case "$1" in
    linux) printf 'linux-headers' ;;
    linux-t2) printf 'linux-t2-headers' ;;
    *) printf '%s-headers' "$1" ;;
  esac
}

append_archzfs_repo() {
  local pacman_conf="$1"

  if ! grep -q '^\[archzfs\]' "$pacman_conf"; then
    cat >>"$pacman_conf" <<'EOF'

[archzfs]
SigLevel = Never
Server = https://github.com/archzfs/archzfs/releases/download/experimental
EOF
  fi
}

configure_zfs_sddm_password_login() {
  mkdir -p /mnt/etc/sddm.conf.d
  cat >/mnt/etc/sddm.conf.d/omarchy-theme.conf <<EOF
[Theme]
Current=omarchy
EOF
  rm -f /mnt/etc/sddm.conf.d/autologin.conf

  mkdir -p /mnt/var/lib/sddm
  cat >/mnt/var/lib/sddm/state.conf <<EOF
[Last]
User=$OMARCHY_USER
Session=hyprland-uwsm
EOF
  if chroot /mnt getent passwd sddm >/dev/null 2>&1; then
    chroot /mnt chown sddm:sddm /var/lib/sddm/state.conf
  fi
}

ensure_zfs_target_mounts() {
  local pool="$1"
  local context="${2:-unspecified}"
  local root_fstype home_source user_home_source log_source expected_user_home

  zfs mount "$pool/ROOT/default" >/dev/null 2>&1 || true
  zfs mount -a

  root_fstype=$(findmnt -n -o FSTYPE --target /mnt 2>/dev/null || true)
  home_source=$(findmnt -n -o SOURCE --mountpoint /mnt/home 2>/dev/null || true)
  user_home_source=$(findmnt -n -o SOURCE --mountpoint "/mnt/home/$OMARCHY_USER" 2>/dev/null || true)
  log_source=$(findmnt -n -o SOURCE --mountpoint /mnt/var/log 2>/dev/null || true)
  expected_user_home=$(zfs_user_home_dataset)

  printf 'ZFS target mount check (%s): /mnt fstype=%s, /mnt/home source=%s, /mnt/home/%s source=%s, /mnt/var/log source=%s\n' "$context" "$root_fstype" "$home_source" "$OMARCHY_USER" "$user_home_source" "$log_source" >&2

  if [[ $root_fstype != "zfs" ]]; then
    echo "Expected /mnt to be mounted from ZFS during $context" >&2
    findmnt -R /mnt >&2 || true
    exit 1
  fi
  if [[ $home_source != "$pool/data/home" ]]; then
    echo "Expected /mnt/home to be mounted from $pool/data/home during $context" >&2
    findmnt -R /mnt >&2 || true
    zfs list -o name,mountpoint,mounted,encryption,keystatus >&2 || true
    exit 1
  fi
  if [[ $user_home_source != "$expected_user_home" ]]; then
    echo "Expected /mnt/home/$OMARCHY_USER to be mounted from $expected_user_home during $context" >&2
    findmnt -R /mnt >&2 || true
    zfs list -o name,mountpoint,mounted,encryption,keystatus >&2 || true
    exit 1
  fi
  if [[ $log_source != "$pool/var/log" ]]; then
    echo "Expected /mnt/var/log to be mounted from $pool/var/log during $context" >&2
    findmnt -R /mnt >&2 || true
    zfs list -o name,mountpoint,mounted,encryption,keystatus >&2 || true
    exit 1
  fi
}

install_zfs_base_system() {
  pacman-key --init
  pacman-key --populate archlinux
  pacman-key --populate omarchy
  pacman -Sy --noconfirm

  findmnt -R /mnt >/dev/null && umount -R /mnt

  local disk boot_part zfs_part pool hostname timezone keyboard kernel_choice kernel_headers
  local user_hash root_hash encryption_password boot_uuid part_uuid zfs_device zfs_home_key zfs_home_dataset
  disk=$(<disk.txt)
  boot_part=$(partition_path "$disk" 1)
  zfs_part=$(partition_path "$disk" 2)
  pool="zroot"
  hostname=$(<hostname.txt)
  timezone=$(<timezone.txt)
  keyboard=$(<keyboard.txt)
  kernel_choice=$(jq -r '.kernels[0] // "linux"' user_configuration.json)
  kernel_headers=$(kernel_headers_for "$kernel_choice")
  user_hash=$(jq -r --arg user "$OMARCHY_USER" '.users[] | select(.username == $user) | .enc_password' user_credentials.json)
  root_hash=$(jq -r '.root_enc_password' user_credentials.json)
  encryption_password=$(jq -r '.encryption_password' user_credentials.json)

  if ((${#encryption_password} < 8)); then
    echo "ZFS encrypted home requires an encryption password of at least 8 characters" >&2
    exit 1
  fi

  if [[ ! -b $disk ]]; then
    echo "Expected install disk $disk to exist" >&2
    exit 1
  fi

  modprobe zfs

  if zpool import -N -f "$pool" >/dev/null 2>&1; then
    zpool destroy -f "$pool"
  fi
  zpool export "$pool" >/dev/null 2>&1 || true

  for dev in "$disk" "${disk}"?*; do
    [[ -b $dev ]] && wipefs -af "$dev" >/dev/null 2>&1 || true
  done

  sgdisk --zap-all "$disk"
  sgdisk \
    --new=1:1MiB:+2GiB --typecode=1:EF00 --change-name=1:EFI \
    --new=2:0:0 --typecode=2:BF00 --change-name=2:zroot \
    "$disk"
  partprobe "$disk" >/dev/null 2>&1 || true
  udevadm settle

  for _ in {1..10}; do
    [[ -b $boot_part && -b $zfs_part ]] && break
    sleep 1
    partprobe "$disk" >/dev/null 2>&1 || true
    udevadm settle
  done

  if [[ ! -b $boot_part || ! -b $zfs_part ]]; then
    echo "Expected partitions $boot_part and $zfs_part to exist" >&2
    exit 1
  fi

  mkfs.fat -F32 -n EFI "$boot_part"

  zfs_device="$zfs_part"
  part_uuid=$(blkid -s PARTUUID -o value "$zfs_part" 2>/dev/null || true)
  if [[ -n $part_uuid && -e /dev/disk/by-partuuid/$part_uuid ]]; then
    zfs_device="/dev/disk/by-partuuid/$part_uuid"
  fi

  zpool create -f \
    -o ashift=12 \
    -o autotrim=on \
    -O acltype=posixacl \
    -O relatime=on \
    -O xattr=sa \
    -O dnodesize=auto \
    -O normalization=formD \
    -O mountpoint=none \
    -O canmount=off \
    -O devices=off \
    -O compression=zstd \
    -R /mnt \
    "$pool" "$zfs_device"

  zfs create -o mountpoint=none "$pool/ROOT"
  zfs create -o mountpoint=/ -o canmount=noauto "$pool/ROOT/default"
  zfs mount "$pool/ROOT/default"

  zfs create -o mountpoint=none "$pool/data"
  zfs create -o mountpoint=/home "$pool/data/home"
  zfs_home_dataset=$(zfs_user_home_dataset)
  zfs_home_key=$(mktemp /tmp/omarchy-zfs-home-key.XXXXXX)
  chmod 600 "$zfs_home_key"
  printf '%s' "$encryption_password" >"$zfs_home_key"
  if ! zfs create \
    -o encryption=on \
    -o keyformat=passphrase \
    -o keylocation="file://$zfs_home_key" \
    -o mountpoint="/home/$OMARCHY_USER" \
    "$zfs_home_dataset"; then
    rm -f "$zfs_home_key"
    exit 1
  fi
  if ! zfs set keylocation=prompt "$zfs_home_dataset"; then
    rm -f "$zfs_home_key"
    exit 1
  fi
  rm -f "$zfs_home_key"
  zfs_home_key=""
  zfs create -o mountpoint=/root "$pool/data/root"
  zfs create -o mountpoint=/srv "$pool/data/srv"
  zfs create -o mountpoint=/var -o canmount=off "$pool/var"
  zfs create "$pool/var/log"
  zfs create -o mountpoint=/var/log/journal -o acltype=posixacl "$pool/var/log/journal"
  zfs create "$pool/var/cache"
  zfs create "$pool/var/tmp"
  zfs create -o mountpoint=/var/lib -o canmount=off "$pool/var/lib"
  zfs create "$pool/var/lib/docker"
  zfs create "$pool/var/lib/libvirt"
  zfs create "$pool/var/lib/machines"
  zpool set bootfs="$pool/ROOT/default" "$pool"
  zpool set cachefile=/etc/zfs/zpool.cache "$pool"
  ensure_zfs_target_mounts "$pool" "after creating and mounting ZFS datasets"

  mkdir -p /mnt/boot /mnt/etc/zfs
  mount "$boot_part" /mnt/boot
  cp /etc/zfs/zpool.cache /mnt/etc/zfs/zpool.cache

  pacstrap -K /mnt \
    base \
    base-devel \
    "$kernel_choice" \
    "$kernel_headers" \
    linux-firmware \
    zfs-utils-git \
    zfs-dkms-git \
    dkms \
    limine \
    sudo \
    git \
    amd-ucode \
    intel-ucode \
    omarchy-keyring
  ensure_zfs_target_mounts "$pool" "after pacstrap"

  boot_uuid=$(blkid -s UUID -o value "$boot_part")
  cat >/mnt/etc/fstab <<EOF
UUID=$boot_uuid /boot vfat umask=0077 0 2
EOF

  cat >/mnt/root/configure-zfs-target.sh <<EOF
#!/bin/bash
set -euo pipefail

ln -sf /usr/share/zoneinfo/$timezone /etc/localtime
hwclock --systohc
sed -i 's/^#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen
printf 'LANG=en_US.UTF-8\n' >/etc/locale.conf
printf 'KEYMAP=$keyboard\n' >/etc/vconsole.conf
printf '$hostname\n' >/etc/hostname

cat >/etc/hosts <<HOSTS
127.0.0.1 localhost
::1 localhost
127.0.1.1 $hostname.localdomain $hostname
HOSTS

printf 'root:%s\n' '$root_hash' | chpasswd -e
useradd -M -d '/home/$OMARCHY_USER' -G wheel -s /bin/bash '$OMARCHY_USER'
install -d -m 700 -o '$OMARCHY_USER' -g '$OMARCHY_USER' '/home/$OMARCHY_USER'
printf '%s:%s\n' '$OMARCHY_USER' '$user_hash' | chpasswd -e
cat >/etc/tmpfiles.d/$OMARCHY_USER-home.conf <<TMPFILES
d /home/$OMARCHY_USER 0700 $OMARCHY_USER $OMARCHY_USER -
TMPFILES
printf '%%wheel ALL=(ALL:ALL) ALL\n' >/etc/sudoers.d/10-wheel
chmod 0440 /etc/sudoers.d/10-wheel

chmod 1777 /var/tmp
ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf || true
zgenhostid deadbeef
zpool set cachefile=/etc/zfs/zpool.cache $pool

if [[ ! -f /usr/lib/security/pam_zfs_key.so ]]; then
  echo "Expected pam_zfs_key.so to be installed by zfs-utils-git" >&2
  exit 1
fi

cat >/etc/pam.d/zfs-key <<PAM
#%PAM-1.0
auth       [default=1 success=ignore] pam_succeed_if.so uid >= 1000 quiet
auth       required                   pam_zfs_key.so homes=$pool/data/home runstatedir=/run/pam_zfs_key
session    [default=2 success=ignore] pam_succeed_if.so uid >= 1000 quiet
session    [success=1 default=ignore] pam_succeed_if.so service = systemd-user quiet
session    optional                   pam_zfs_key.so homes=$pool/data/home runstatedir=/run/pam_zfs_key
password   [default=1 success=ignore] pam_succeed_if.so uid >= 1000 quiet
password   required                   pam_zfs_key.so homes=$pool/data/home runstatedir=/run/pam_zfs_key
PAM

for pam_file in /etc/pam.d/system-auth /etc/pam.d/su-l; do
  grep -Eq '^auth[[:space:]]+include[[:space:]]+zfs-key' "\$pam_file" || sed -i '1aauth       include      zfs-key' "\$pam_file"
  grep -Eq '^session[[:space:]]+include[[:space:]]+zfs-key' "\$pam_file" || sed -i '1asession    include      zfs-key' "\$pam_file"
  grep -Eq '^password[[:space:]]+include[[:space:]]+zfs-key' "\$pam_file" || sed -i '1apassword   include      zfs-key' "\$pam_file"
done

sed -i 's/^MODULES=.*/MODULES=(zfs)/' /etc/mkinitcpio.conf
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block zfs filesystems)/' /etc/mkinitcpio.conf
# In a chroot, uname -r is still the live ISO kernel. Build only for target kernels.
for modules_dir in /usr/lib/modules/*; do
  [[ -d "\$modules_dir" ]] || continue
  dkms autoinstall -k "\$(basename "\$modules_dir")"
done
mkinitcpio -P

mkdir -p /boot/EFI/BOOT /boot/EFI/arch-limine
cp /usr/share/limine/BOOTX64.EFI /boot/EFI/BOOT/BOOTX64.EFI
cp /usr/share/limine/BOOTX64.EFI /boot/EFI/arch-limine/BOOTX64.EFI

cat >/boot/EFI/BOOT/limine.conf <<LIMINE
timeout: 3

/+Arch Linux ZFS
    protocol: linux
    path: boot():/vmlinuz-$kernel_choice
    cmdline: root=ZFS=$pool/ROOT/default rw zfs_boot_only=1 console=ttyS0,115200n8 console=tty1
    module_path: boot():/initramfs-$kernel_choice.img

/+Arch Linux ZFS fallback
    protocol: linux
    path: boot():/vmlinuz-$kernel_choice
    cmdline: root=ZFS=$pool/ROOT/default rw zfs_boot_only=1 console=ttyS0,115200n8 console=tty1
    module_path: boot():/initramfs-$kernel_choice-fallback.img
LIMINE

cp /boot/EFI/BOOT/limine.conf /boot/EFI/arch-limine/limine.conf

systemctl enable systemd-networkd.service
systemctl enable systemd-resolved.service
systemctl enable serial-getty@ttyS0.service
systemctl enable zfs-import-cache.service
systemctl enable zfs-import.target
systemctl enable zfs-mount.service
systemctl enable zfs.target
EOF

  chmod +x /mnt/root/configure-zfs-target.sh
  arch-chroot /mnt /root/configure-zfs-target.sh
  rm /mnt/root/configure-zfs-target.sh

  ensure_zfs_target_mounts "$pool" "after configuring ZFS target"
  prepare_target_for_omarchy
}

chroot_bash() {
  HOME=/home/$OMARCHY_USER \
    arch-chroot -u $OMARCHY_USER /mnt/ \
    env OMARCHY_CHROOT_INSTALL=1 \
    OMARCHY_USER_NAME="$(<user_full_name.txt)" \
    OMARCHY_USER_EMAIL="$(<user_email_address.txt)" \
    OMARCHY_MIRROR="$OMARCHY_MIRROR" \
    OMARCHY_ZFS_HOME_PROBE="$(zfs_home_probe_name)" \
    USER="$OMARCHY_USER" \
    HOME="/home/$OMARCHY_USER" \
    /bin/bash "$@"
}

if [[ $(tty) == "/dev/tty1" ]]; then
  use_omarchy_helpers
  run_configurator
  install_arch
  install_omarchy
fi
