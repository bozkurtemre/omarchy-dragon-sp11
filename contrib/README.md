# Upstream contributions

What is still worth sending upstream from this Surface Pro 11 LCD (Snapdragon X Plus X1P64100,
panel `LGD077b`). Nothing here is opened yet. The two patches this folder held until 2026-11-19, for
omarchy and omarchy-pkgs, are superseded by omarchy PR #18276 and omarchy-pkgs #2378, #2379 and #2382
and were removed; they are in the git history.

## 1. systemd: `systemd-x1p64100-microsoft-denali.json`

For `src/boot/hwids/aa64/x1p64100-microsoft-denali.json`, beside systemd's
`x1e80100-microsoft-denali.json` (the OLED model). The OLED, LCD and 5G models share every SMBIOS
field, so systemd's own entry sends all of them to `microsoft,denali-oled`. This entry carries only
the three CHIDs that include the panel's EDID ID, systemd's extra types `EXTRA_CHID_BASE + 0..2`
(manufacturer + family + product name + panel, manufacturer + family + panel, manufacturer + SKU +
panel), which `chid_match()` tries before any SMBIOS-only CHID. On the LCD model the stub then picks
`microsoft,denali-lcd`; everywhere else it falls through to the OLED entry.

Provenance of the three GUIDs:

- Omarchy already ships the same file, byte for byte, in `linux-omarchy-dtbs` 7.3-52
  (`/usr/lib/systemd/boot/hwids/aa64/linux-omarchy/`), and its live UKI's `.hwids` carries the three
  CHIDs.
- `tools/sp11-chid.ps1 -HwidsJson contrib/systemd-x1p64100-microsoft-denali.json -Panel LGD077B`
  computes them on this machine from its SMBIOS fields, and `build/edge/hwids.py` computes them from
  the `device-facts.json` the build records (`test/edge-test.sh` checks both).
- The panel ID is `LGD077b`: systemd writes the EDID product code as lowercase hex. This folder's
  first version used `LGD077B`, which gives three other GUIDs that match nothing; that was wrong.

Before opening: on the installed system, `systemd-analyze chid` must list the three GUIDs among its
EDID-based CHIDs, and the live session must have come up with `/proc/device-tree/model` reading
"(LCD)" on Omarchy's unmodified live UKI. That second check is also the open question in the main
README ("If the live session runs the OLED tree"): it shows whether the Surface firmware hands
systemd-stub the panel's EDID at all. If it does not, this entry cannot work on this hardware and
should not be sent.

## 2. linux-firmware has an exact Wi-Fi board record now

The WCN7850 in every Snapdragon Surface reports subsystem `17cb:1107` and board-id 255, which
linux-firmware's `ath12k/WCN7850/hw2.0/board-2.bin` did not list, so `microsoft-surface-pro-11-support`
ships Qualcomm's reference-design record (`subsystem-device=3378`, board-id 255) as `board.bin`.
linux-firmware commit `575bbe3f` (tag 20261019) added an exact
`bus=pci,vendor=17cb,device=1107,subsystem-vendor=17cb,subsystem-device=1107,qmi-chip-id=2,qmi-board-id=255`
record, and the edge root image's `linux-firmware-atheros` 20261019-1 carries it (checked by
`build/edge/verify-edge-iso.sh`, section 6). ath12k prefers an exact `board-2.bin` match over
`board.bin`, so on edge the package's `board.bin` should no longer be read.

For omarchy-pkgs, once Wi-Fi is confirmed on hardware (`sudo dmesg | grep -i 'ath12k.*board'` names
the file it loaded): the support package's README says to drop its board data "once linux-firmware
carries a Surface Pro 11 entry". Whether the new record is Surface calibration or another reference
board is not known; this machine's own Windows board files (`bdwlan*` in `qcwlanhmt8380`) are in the
USB's driver archive for that comparison.
