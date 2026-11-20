# sp11-lcd: this Surface Pro 11's Windows files, for Omarchy

This folder sits at the root of the USB stick (`/sp11-lcd`), built by
[omarchy-dragon-sp11](https://github.com/bozkurtemre/omarchy-dragon-sp11) on one Surface Pro 11
LCD (Snapdragon X Plus X1P64100). Omarchy's own edge installer does everything else; this folder
only carries what a full-disk install erases with Windows.

| Path | What it is |
|---|---|
| `setup.sh` | Run once on the installed system (below) |
| `windows/FileRepository/` | Every driver package in this machine's Windows driver store whose INF names Surface, Qualcomm or Dolby as its provider: DSP, GPU and video firmware, the light sensor configuration, the Dolby speaker tuning, camera tuning, Wi-Fi and Bluetooth board data, touch, pen and UEFI firmware packages |
| `windows/device-facts.json` | SMBIOS fields, firmware versions, SoC, the panel's EDID ID, Wi-Fi, Bluetooth and audio IDs, the Wi-Fi and Bluetooth addresses Windows used. No recovery key, product key, serial number or account data |
| `windows/SHA256SUMS` | SHA256 of every file under `windows/` |

These are Microsoft, Qualcomm and Dolby files for this one device. Don't share the stick or the
ISO.

## After the first boot of the installed system

```
sudo mount -o ro /dev/disk/by-label/OMARCHY_* /mnt    # lsblk -f shows the stick's label
sudo bash /mnt/sp11-lcd/setup.sh
sudo umount /mnt
```

`setup.sh` checks the archive on the stick, copies it to `/var/lib/sp11-lcd/windows` (readable by
root only) and checks the copy, then runs Omarchy's `surface-pro-11-sensors-extract` on it, which
sets up the light sensor (auto brightness), and restarts `surface-pro-11-sensors.service`. It
changes nothing else and can be rerun.

Omarchy's Surface Pro 11 step enables that service during the install. If `setup.sh` warns that it
is not enabled, that step did not run as it should: check `tr -d '\0' </proc/device-tree/model`
and `cat /sys/devices/soc0/soc_id` (main README, "First boot"), then
`sudo systemctl enable --now surface-pro-11-sensors.service`.

The copy on the installed system is gone after *Remove > Factory Reset* (Omarchy swaps the root
subvolume for its install-time snapshot). Run `setup.sh` again from this stick or from your other
copy afterwards. To set up only the light sensor again from the copy on the system:

```
sudo surface-pro-11-sensors-extract -d /var/lib/sp11-lcd/windows/FileRepository
```
