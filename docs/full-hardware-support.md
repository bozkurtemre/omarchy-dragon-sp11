# Getting sound, touch, sensors and Bluetooth working: options

Research notes, 2026-11-08. Everything below was checked against the official 4.5.0 aarch64 ISO,
Omarchy's package repositories, the omarchy-pkgs sources (quattro, 2026-11-07) and this machine's
Windows driver store. Nothing has been run on the Surface yet.

## What is missing on stable, and why

Omarchy's Surface Pro 11 support is complete on the **edge** repository and absent from stable and
rc (both carry the same 219 packages). The pieces:

| Package (edge only) | Gives | OLED-gated? |
|---|---|---|
| `microsoft-surface-pro-11-support` 1-7 | Speaker topology + UCM, speaker protection limiter (PipeWire filter chain), Wi-Fi board data, Flex Keyboard Bluetooth pairing, pen pairing, lid/charge/touchpad/iptsd sleep hooks, camera tweaks | yes: 8 files check `microsoft,denali-oled` (5 scripts, 2 units via `ConditionFirmware=`, 1 Python) |
| `microsoft-surface-pro-11-sensors` 1-1 | Ambient light sensor (auto brightness) through the ADSP (`hexagonrpcd` + `libssc`), configuration extracted from Windows | yes: service `ConditionFirmware=`, extract script, sleep hook |
| `iptsd` 3.1.0-2 | Touchscreen and pen from the digitizer's raw reports | no (detects by HID report descriptor, not by model) |
| `microsoft-surface-snapdragon-addresses` 1-2 | Bluetooth public address and a stable Wi-Fi MAC from the `MacAddressEmulationAddress` UEFI variable. Without it the WCN7850 stays an unconfigured Bluetooth controller | no (DMI vendor + UEFI variable) |
| `microsoft-surface-pro-11-firmware` 20261102-2 | The same DSP/GPU firmware we stage from the driver store, from Microsoft's MSI | no |

Omarchy's own install step for these (`install/hardware/microsoft/surface-pro-11.sh`) exists only on
the quattro branch, i.e. the `omarchy-dev` package. The `omarchy` 4.5.0-3 runtime is identical on
stable and edge, so even on edge nothing installs them automatically today; our `apply.sh` has to.

## What this LCD unit shares with the OLED unit Omarchy tested

| Check | Result |
|---|---|
| Sound card | The `sound` node, `model = "X1E80100-Microsoft-Surface-Pro-11"` and the WSA8845 speaker routing live in the shared `x1-microsoft-denali.dtsi`, so the topology file name, UCM match and mixer paths are the same on the LCD tree. Only the panel node differs between the two `.dts` files. |
| Speaker tuning | Windows' audio device on this unit is `AUCD\VEN_QCOM&DEV_0C29&SUBSYS_MSHW0486&REV_0D`: the exact Dolby tuning ID the package's limiter was generated from. |
| Digitizer | `HID\MSHW0484` (Surface Touch G6, pen collections), the same digitizer family; iptsd accepts any device whose HID descriptor has the IPTS touch-data and mode-setting reports. |
| Sensor configuration | `surfacepro_snscfgcrd8380.inf_arm64_*` is in this unit's driver store with `json.lst`, `sns_reg_config`, and `8380_crd_tcs3430_0.json` / `sns_surface_color.json` whose SHA256 match the hashes the extract script qualified on hardware. |
| Kernel | Every Surface Pro 11 patch of the edge kernel (7.3-32) is already in the stable kernel (7.3-3.1 = pkgrel 3 of 2026-10-26): platform support (2152), cameras (2161–2169), KIP out-of-band pairing (2140), battery charge limits (2133), tablet mode (2130–2132), ADSP power limits (2176). The 244 patches edge added since are for other laptops (Glymur, Surface Laptop 8, …). |
| UCM base files | The support package's UCM includes `codecs/wsa884x/two-speakers/init.conf` etc.; all present in stable's `alsa-ucm-conf` 1.2.16.1. |
| Dependencies | `fmt`, `spdlog`, `lsp-plugins-lv2`, `iio-sensor-proxy`, `libqmi`, `libqrtr-glib`, `protobuf-c`, `pipewire-libcamera` are all on the stable (one-month-behind) ARM mirror; `libinih` is already in the root image. None are on the target image yet except `libinih` and `bluez`. |

So the only things standing between this unit and full support are (1) where the five packages
come from and (2) the `denali-oled` string in 11 files.

## Options

### A. Switch the installed system to the edge channel
`omarchy-channel-set edge`, then install the five packages.

- Pro: everything official and signed; Omarchy's own path for Snapdragon users today.
- Con: the whole system follows edge: kernel 7.3-32, Hyprland 0.57, current ALARM instead of the
  one-month-behind mirror. The manual says edge is for people who can recover a broken system. The
  OLED gate still needs the local fix below.

### B. Stay on stable, take only the five packages from edge (recommended)
Add the edge repository **after** `[core]`/`[extra]`/`[alarm]` in `/etc/pacman.conf`:

```ini
[omarchy-edge]
Server = https://pkgs.omarchy.org/edge/$arch
```

pacman takes a package from the first repository that has it, so with the entry last, edge supplies
only what nothing else has: exactly the five packages (and `ath12k-board-fallback`,
`linux-firmware-qcom`, which we don't need). Kernel, Hyprland, Omarchy runtime and all libraries stay
stable. The packages are signed with the same Omarchy key the stable repo uses.

- Persistence: `omarchy-channel-set` and `omarchy-refresh-pacman` rewrite `/etc/pacman.conf` from
  templates, but run `omarchy-hook pre-refresh-pacman` first, "so custom repositories … shape the
  transaction". A hook in `~/.config/omarchy/hooks/pre-refresh-pacman` that re-appends the entry
  keeps it across channel changes. Routine `omarchy-update` does not rewrite `pacman.conf`.
- Risk: if edge rebuilds one of the five against a library soname stable does not have yet, pacman
  refuses the update with a visible dependency error until the stable mirror catches up (at most a
  month). Today the versions match (`fmt` 12.2.0, `spdlog` 1.17.0 on both mirrors).
- Offline install: the live USB has no Wi-Fi (no board data, DSP off), so `finish-install.sh` cannot
  download. The ISO build can pre-fetch the five packages, their missing dependencies and all
  `.sig` files from the two official repositories, resolved by pacman inside the official target root
  image (the `test/` harness already mounts it). `pacman -U` then installs the same signed packages
  the online path would, verified with the keyrings already in the image.

### C. Build the packages locally from Omarchy's PKGBUILDs, with the gate fixed, as an offline repo
The Surface Laptop 7 port does this.

- Pro: no edge repository on the machine; the gate is fixed at build time.
- Con: an aarch64 Arch build environment, rebuilding whenever omarchy-pkgs changes, and the packages
  are foreign to Omarchy updates. More work for the same bits that B gets signed from Omarchy.

### D. Upstream (complements A or B)
1. omarchy-pkgs: check `microsoft,denali` instead of `microsoft,denali-oled` in the support and
   sensors packages (11 files). The LCD shares every node those scripts touch.
2. omarchy (quattro): `install/hardware/microsoft/surface-pro-11.sh` gains an LCD branch that pins
   `x1p64100-microsoft-denali.dtb` and early-loads `panel-edp`.
3. systemd: `src/boot/hwids/aa64/x1p64100-microsoft-denali.json` for `microsoft,denali-lcd`. The EDID
   panel CHIDs (LGD077B) outrank the SMBIOS-only ones, so the stub would pick the LCD tree by itself.

The Snapdragon side of omarchy-pkgs merged 20+ device-tree changes in the week before 2026-11-07,
so small, well-evidenced PRs tend to land fast; a timeline is still not something to depend on.

## The OLED gate: local fix for A and B
A pacman hook (`PostTransaction`, `Target = microsoft-surface-pro-11-support` and
`-sensors`) that replaces `microsoft,denali-oled` with `microsoft,denali` in the installed scripts
and units, then `systemctl daemon-reload`. It survives package updates and goes away by itself once
upstream makes the change (nothing left to replace).

## What B changes in `apply.sh`
1. Append `[omarchy-edge]` (or point pacman at the USB's package cache when offline).
2. Install `microsoft-surface-pro-11-firmware`, `-support` (pulls `-snapdragon-addresses`), `iptsd`,
   `-sensors`, `pipewire-libcamera`. The firmware package replaces the driver-store copies
   (`qcom-firmware-extract --retire` does that itself); the package's `board.bin` replaces ours.
3. `surface-pro-11-sensors-extract -d <staged driver store>`; `systemctl enable surface-pro-11-sensors`
   and the Flex Keyboard units.
4. Install the gate hook and the `pre-refresh-pacman` hook.
5. Keep the driver-store firmware path as the offline fallback.

## Still unknowable before a hardware test
Pen pressure/tilt through iptsd, whether the LCD's speakers want the same ceilings (same tuning ID
says yes), the light sensor's calibration, suspend/resume and the Flex Keyboard pairing. None of this
can be checked in the container.
