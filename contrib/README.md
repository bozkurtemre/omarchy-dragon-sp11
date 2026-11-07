# Upstream contributions

Three changes that make the Surface Pro 11 LCD (Snapdragon X Plus) a first-class citizen upstream,
so that this repository's fix becomes unnecessary. All three are prepared here; **none is opened
yet**: every check they relax was put there by its maintainers because only the OLED model had been
tested, and the evidence they need is a hardware test on this LCD unit. Open them, in this order,
once `README.md`'s first-boot checks pass.

## 1. omarchy-pkgs: `omarchy-pkgs-surface-pro-11-lcd.patch`

`microsoft-surface-pro-11-support` and `-sensors` check for `microsoft,denali-oled`; the patch
checks for `microsoft,denali`, which both models carry, and says so in the READMEs and `pkgdesc`.
The fixtures in `test.sh` carry `microsoft,denali` as their second compatible, so the tests pass
unchanged.

Apply on the `quattro` branch: `git apply contrib/omarchy-pkgs-surface-pro-11-lcd.patch`.

Evidence to put in the PR: the sound card, speaker routing and digitizer nodes live in
`x1-microsoft-denali.dtsi` (shared); this unit's Windows audio device is
`VEN_QCOM&DEV_0C29&SUBSYS_MSHW0486&REV_0D`, the tuning the speaker limiter was generated from;
`8380_crd_tcs3430_0.json` and `sns_surface_color.json` in its driver store have the hashes the
sensors extract script qualified; and the hardware test results (speakers, microphones, touch, pen,
auto brightness, Flex Keyboard pairing, suspend).

## 2. omarchy: `omarchy-surface-pro-11-lcd.patch`

`install/hardware/microsoft/surface-pro-11.sh` matches the OLED or the LCD tree, pins the matching
`.dtb` (`x1p64100-microsoft-denali.dtb` on the LCD) and early-loads `panel_edp` next to the OLED's
Samsung panel driver. A bare `microsoft,denali` (neither model) is still left alone.
`test/shell.d/surface-pro-11-hardware-test.sh` gains an LCD fixture that fails on the base branch.

Apply on the `quattro` branch: `git apply contrib/omarchy-surface-pro-11-lcd.patch`, then run
`bash test/shell.d/surface-pro-11-hardware-test.sh >/tmp/sp11.log 2>&1` as a non-root user.

## 3. systemd: `systemd-x1p64100-microsoft-denali.json`

`src/boot/hwids/aa64/x1p64100-microsoft-denali.json`. The OLED, LCD and X Plus models share every
SMBIOS field, so an entry built from SMBIOS CHIDs would be ambiguous. This one carries only the
three EDID-panel CHIDs (systemd's extra types `EXTRA_CHID_BASE + 0..2`: manufacturer + family +
product + panel, manufacturer + family + panel, manufacturer + SKU + panel) for this unit's panel
`LGD077B`, which `chid_match()` tries before any SMBIOS-only CHID, so the stub picks the LCD tree on
the LCD and falls through to the OLED entry elsewhere. Computed by `tools/sp11-chid.ps1` from this
machine's SMBIOS fields and the panel's EDID ID.

Verify on the installed system before opening: `systemd-analyze chid` prints the CHIDs the real
code computes, including the EDID ones (type letter `E`); the three GUIDs above must appear. Then a
boot test: a UKI with both Denali trees as `.dtbauto` and a `.hwids` section built from systemd's
`aa64/` plus this file must come up with `/proc/device-tree/model` reading "(LCD)".
