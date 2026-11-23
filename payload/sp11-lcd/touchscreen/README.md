# Turning the touchscreen off

Omarchy's *Triggers > Hardware > Disable Touchscreen* (and `omarchy device touchscreen`) does
nothing on the Surface Pro 11: finger touch keeps working.

Hyprland has two touch devices here:

| Device | What it carries |
|---|---|
| `spi-045e:0c80-touchscreen` | The kernel's HID-over-SPI touchscreen. iptsd reads the touch data itself, so no events arrive here |
| `iptsd-virtual-touchscreen-045e:0c80` | Finger touch, as iptsd sends it |

`omarchy-hw-touchscreen` picks the first touch device, the SPI one. Turning it off changes
nothing. Turning off only the iptsd device stops finger touch, and the pen (a tablet device) keeps
working.

## Setup

Run as your own user, without sudo:

```bash
bash /mnt/sp11-lcd/touchscreen/setup-touchscreen.sh    # from the USB stick, mounted as in ../README.md
# or, from a checkout of this repository:
bash payload/sp11-lcd/touchscreen/setup-touchscreen.sh
```

It does two things:

1. Installs `surface-touchscreen` as `~/.local/bin/surface-touchscreen`. It turns every Hyprland
   touch device on or off together and leaves the tablet devices alone. It uses Omarchy's own state
   file, `~/.local/state/omarchy/toggles/hypr/touchscreen-disabled-name`, and writes the iptsd
   device's name into it. The menu then shows the right entry, and Omarchy's
   `disabled-input-device.lua` turns that device off again on every Hyprland reload and login.
2. Copies `trigger.hardware.touchscreen-on` and `-off` from Omarchy's menu
   (`/usr/share/omarchy/default/omarchy/omarchy-menu.jsonc`) into a marked block in
   `~/.config/omarchy/extensions/omarchy-menu.jsonc`. Only the action changes, to
   `surface-touchscreen on|off`. The icon, label and `when` condition are copied too: menu search
   shows an override without a label by its id (`hardware.touchscreen-off`).

The menu reloads by itself. You can rerun the script: it replaces its own block, keeps the rest of
the file and backs the file up before changing it. It stops if Omarchy's entries no longer run
`omarchy-device-touchscreen` (Omarchy may have fixed this), or if the file already overrides these
ids outside its block.

From a terminal, use `surface-touchscreen on|off|toggle`. `omarchy device touchscreen` still turns
off the SPI device only.

## Tested

2026-11-23, on this Surface Pro 11 LCD (iptsd on `/dev/hidraw4`):

- Turning off only `iptsd-virtual-touchscreen-045e:0c80` stopped finger touch. The pen kept working.
- Turned off through the script, touch stayed off after `hyprctl reload`, with no config errors.
- Enable and Disable Touchscreen from the menu both worked. Search lists them by their labels.
- The script on a scratch home: inserted the block after an entry without a trailing comma, a rerun
  changed nothing, it created the file when there was none, and it stopped on an existing override.

## Removing it

Delete the block between the `BEGIN sp11-lcd touchscreen` and `END sp11-lcd touchscreen` lines in
`~/.config/omarchy/extensions/omarchy-menu.jsonc`, then `rm ~/.local/bin/surface-touchscreen`.
