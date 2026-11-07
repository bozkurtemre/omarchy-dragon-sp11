# sp11-lcd: post-install fix for the Surface Pro 11 LCD (Snapdragon X Plus)

This folder sits at the root of the USB stick (`/sp11-lcd`). Run it once after the Omarchy
installer finishes, **before rebooting**.

1. When the installer shows its "done" screen, don't reboot.
2. Press `Ctrl+Alt+F2` and log in as `root` (no password).
3. Run:

   ```
   bash /run/archiso/bootmnt/sp11-lcd/finish-install.sh
   ```

4. Enter the disk encryption password if asked. It must end with `It is safe to reboot.`
5. Type `reboot` and pull the USB stick once the screen goes black.

If you already rebooted and the installed system came up, plug the stick in and run from it:

```
sudo bash <usb>/sp11-lcd/apply.sh <usb>/sp11-lcd
```

## What it does

- Pins the LCD device tree (`x1p64100-microsoft-denali.dtb`) in the UKI and keeps it pinned on every
  kernel/UKI rebuild (`/etc/boot/hooks/pre.d/90-sp11-lcd-devicetree`). Otherwise systemd-stub loads
  the OLED tree on every Surface Pro 11.
- Adds the panel, display and Surface keyboard drivers to the initramfs
  (`/etc/mkinitcpio.conf.d/zz-sp11-lcd.conf`), so the disk unlock prompt is visible and the keyboard works.
- Installs this device's signed ADSP/CDSP/GPU firmware, taken from its Windows driver store, with
  Omarchy's `qcom-firmware-extract`, and enables the DSP driver once nothing is missing.
- Installs Omarchy's Surface Pro 11 packages from `pkgs/` (sound with speaker protection, touch and
  pen, light sensor, Bluetooth address, firmware), makes them act on the LCD model, extracts the light
  sensor's configuration from `sensors/`, and hooks their updates into `omarchy-update`
  (`sp11-lcd-update`, which can also be run by hand).
- Installs the Wi-Fi board data the Surface's WCN7850 finds nowhere else (Qualcomm's reference
  record, as Omarchy's Surface Pro 11 package does).
- Rebuilds the boot image and verifies that the UKI that will boot really uses the LCD tree.

The scripts are copied to `/usr/local/lib/sp11-lcd/`. Rerun them any time with
`sudo /usr/local/lib/sp11-lcd/apply.sh /usr/local/lib/sp11-lcd` (packages, firmware and sensor
configuration stay as they are; everything else is reapplied).
