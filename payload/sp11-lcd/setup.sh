#!/bin/bash
# Keep this Surface Pro 11's Windows driver archive on the installed Omarchy
# system and set up the light sensor from it.
#
# Run once on the installed system, after its first boot, with the USB stick
# this script came on mounted (README.md next to it):
#   sudo mount -o ro /dev/disk/by-label/OMARCHY_* /mnt
#   sudo bash /mnt/sp11-lcd/setup.sh
#
#  1. Checks windows/ on the stick against its SHA256SUMS.
#  2. Copies it to /var/lib/sp11-lcd/windows (root only) and checks the copy.
#  3. Runs Omarchy's surface-pro-11-sensors-extract on the copy: the light
#     sensor configuration upstream reads from the Windows partition, which a
#     full-disk install has erased.
#  4. Restarts surface-pro-11-sensors.service, which Omarchy's Surface Pro 11
#     setup has already enabled.
# Safe to rerun; nothing else on the system is changed.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
dest=${SP11_LCD_DEST:-/var/lib/sp11-lcd}
compatible=${SP11_SENSORS_COMPATIBLE:-/proc/device-tree/compatible}
sensors_root=${SP11_SENSORS_ROOT:-/var/lib/surface-pro-11-sensors/root}

die() { echo "sp11-lcd: ERROR: $*" >&2; exit 1; }
warn() { echo "sp11-lcd: WARNING: $*" >&2; }
step() { echo; echo "==> $*"; }

((EUID == 0)) || die "run as root: sudo bash $here/setup.sh"
[[ ! -d /run/archiso ]] || die "this is the live USB session; run this on the installed system after its first boot"
[[ -d /usr/share/omarchy ]] || die "no Omarchy installation here"
[[ -f $here/windows/SHA256SUMS && -d $here/windows/FileRepository ]] || die "no windows/ archive next to this script"
# surface-pro-11-sensors-extract quietly does nothing on another device tree.
tr '\0' '\n' 2>/dev/null <"$compatible" | grep -qx 'microsoft,denali' ||
  die "the running device tree is not a Surface Pro 11's (no microsoft,denali in $compatible)"
command -v surface-pro-11-sensors-extract >/dev/null ||
  die "surface-pro-11-sensors-extract is missing; Omarchy's Surface Pro 11 setup installs microsoft-surface-pro-11-sensors"

step "Checking the archive on the USB stick"
(cd "$here/windows" && sha256sum --quiet -c SHA256SUMS) || die "the archive on the stick is damaged; write the ISO again"
echo "$(wc -l <"$here/windows/SHA256SUMS") files match SHA256SUMS"

step "Copying it to $dest/windows (root only)"
install -d -m 0700 -o root -g root "$dest"
tmp=$(mktemp -d "$dest/.windows.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
cp -r --preserve=timestamps "$here/windows/." "$tmp/"
chown -R root:root "$tmp"
chmod -R u=rwX,go= "$tmp"
(cd "$tmp" && sha256sum --quiet -c SHA256SUMS) || die "the copy in $tmp does not match SHA256SUMS"
rm -rf "$dest/windows.old"
if [[ -e $dest/windows ]]; then mv "$dest/windows" "$dest/windows.old"; fi
mv "$tmp" "$dest/windows"
rm -rf "$dest/windows.old"
trap - EXIT
echo "$(du -sh "$dest/windows" | cut -f1) in $dest/windows"

step "Light sensor configuration"
surface-pro-11-sensors-extract -d "$dest/windows/FileRepository"
for f in sensors/config/json.lst sensors/sns_reg.conf socinfo/soc_id; do
  [[ -s $sensors_root/$f ]] || die "$sensors_root/$f is missing after the extraction"
done
if [[ ! -d /run/systemd/system ]]; then
  echo "Not running under systemd; the sensor service starts at the next boot"
elif systemctl is-enabled --quiet surface-pro-11-sensors.service; then
  systemctl restart surface-pro-11-sensors.service ||
    warn "surface-pro-11-sensors.service did not start now; reboot, then check 'systemctl status surface-pro-11-sensors'"
else
  warn "surface-pro-11-sensors.service is not enabled, though Omarchy's Surface Pro 11 setup enables it; see $here/README.md"
fi

echo
echo "sp11-lcd: done. The Windows archive is in $dest/windows; keep another copy off this machine too."
