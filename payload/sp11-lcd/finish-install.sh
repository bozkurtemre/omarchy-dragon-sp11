#!/bin/bash
# Finish an Omarchy install on the Surface Pro 11 LCD (Snapdragon X Plus).
#
# From the sp11-lcd live USB, right after the installer says it is done and
# BEFORE rebooting: press Ctrl+Alt+F2, log in as root, and run
#   bash /run/archiso/bootmnt/sp11-lcd/finish-install.sh
# It unlocks and mounts the new install, runs apply.sh inside it, checks the
# UKI that will boot, and releases everything again.
#
# On an already booted install, run apply.sh instead (see README.md).
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
die() { echo "sp11-lcd: ERROR: $*" >&2; exit 1; }

((EUID == 0)) || die "run as root"
if [[ ! -d /run/archiso ]]; then
  die "this is not the live USB; on the installed system run: sudo bash $here/apply.sh $here"
fi

target=/mnt/sp11-lcd
mapper=""
opened=0
cleanup() {
  set +e
  rm -rf "$target/var/tmp/sp11-lcd" 2>/dev/null
  if mountpoint -q "$target"; then
    umount -R "$target"
  fi
  if ((opened)); then
    cryptsetup close "$mapper"
  fi
}
trap cleanup EXIT

# The install target is on an internal disk, never on the boot medium.
boot_disk=$(lsblk -no PKNAME "$(findmnt -no SOURCE /run/archiso/bootmnt)" 2>/dev/null | head -1)
mapfile -t luks < <(lsblk -rpno NAME,FSTYPE,PKNAME | awk -v b="/dev/$boot_disk" '$2 == "crypto_LUKS" && $3 != b { print $1 }')

if ((${#luks[@]} > 1)); then
  echo "Several encrypted partitions found:"
  select dev in "${luks[@]}"; do [[ -n $dev ]] && break; done
  luks=("$dev")
fi

if ((${#luks[@]} == 1)); then
  dev=${luks[0]}
  # Reuse a mapping the installer left open.
  mapper=$(lsblk -rno NAME,TYPE "$dev" | awk '$2 == "crypt" { print $1; exit }')
  if [[ -z $mapper ]]; then
    mapper=sp11root
    echo "Unlocking $dev (the disk encryption password you chose in the installer)"
    cryptsetup open "$dev" "$mapper"
    opened=1
  fi
  root=/dev/mapper/$mapper
else
  mapfile -t btrfs < <(lsblk -rpno NAME,FSTYPE,PKNAME | awk -v b="/dev/$boot_disk" '$2 == "btrfs" && $3 != b { print $1 }')
  ((${#btrfs[@]} == 1)) || die "cannot find the installed system (no single LUKS or btrfs partition on an internal disk)"
  root=${btrfs[0]}
fi

# Read the root subvolume from the install's own fstab, then mount the rest
# (including whichever EFI partition the install uses) the same way.
mkdir -p "$target"
mount -o subvolid=5 "$root" "$target"
fstab=""
for candidate in "$target/@/etc/fstab" "$target/etc/fstab"; do
  [[ -f $candidate ]] && { fstab=$candidate; break; }
done
[[ -n $fstab ]] || die "no etc/fstab on $root"
subvol=$(awk '$2 == "/" { n = split($4, o, ","); for (i = 1; i <= n; i++) if (o[i] ~ /^subvol=/) { sub(/^subvol=/, "", o[i]); print o[i] } }' "$fstab")
umount "$target"
if [[ -n $subvol ]]; then
  mount -o "subvol=$subvol" "$root" "$target"
else
  mount "$root" "$target"
fi
# Everything but / and swap, including noauto/automount entries such as an ESP.
fstab_rest=$(mktemp)
awk '!/^[[:space:]]*(#|$)/ && $2 != "/" && $3 != "swap" {
  n = split($4, o, ","); opts = ""
  for (i = 1; i <= n; i++) if (o[i] != "noauto" && o[i] !~ /^x-systemd\./) opts = opts (opts ? "," : "") o[i]
  $4 = opts ? opts : "defaults"; print }' "$target/etc/fstab" >"$fstab_rest"
mount --all --fstab "$fstab_rest" --target-prefix "$target"
rm -f "$fstab_rest"
findmnt -R "$target" -no TARGET,SOURCE,FSTYPE

rm -rf "$target/var/tmp/sp11-lcd"
cp -r "$here" "$target/var/tmp/sp11-lcd"
arch-chroot "$target" bash /var/tmp/sp11-lcd/apply.sh /var/tmp/sp11-lcd "$@"
echo
echo "sp11-lcd: Type 'reboot'. Pull the USB once the screen goes black, so the Surface starts the installed system."
