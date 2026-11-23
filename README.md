# omarchy-dragon-sp11

**English** | [Türkçe](README.tr.md)

[Omarchy](https://omarchy.org) on the **Microsoft Surface Pro 11, LCD / Snapdragon X Plus (X1P64100,
`microsoft,denali-lcd`)**, from Omarchy's own aarch64 **edge** ISO, plus the one thing upstream cannot
ship: this machine's own Windows files, which a full-disk install erases.

> **Status, 2026-11-20:** nothing has been booted on hardware with the edge ISO yet. A trial boot of
> this repository's earlier, 4.5.0-based ISO reached the installer on the LCD panel on 2026-11-08.
> The ISO built here passes the container tests below; results from the Surface will be added here.

## What Omarchy does now

The LCD model is supported upstream, on the edge channel only (stable and rc are still 4.5.0-3, and
no release newer than 4.5.0 exists):

- **omarchy [PR #18276](https://github.com/omacom/omarchy/pull/18276)** by Iván Ruiz (rdereparadores),
  merged 2026-11-11 (`b19ad9764d78`): `install/hardware/microsoft/surface-pro-11.sh` matches any
  Surface Pro 11 (`microsoft,denali`), pins `x1p64100-microsoft-denali.dtb` in the UKI when
  `/sys/devices/soc0/soc_id` is 615 (X1P-64-100), loads `panel_edp`, `pwm_bl` and `leds_qcom_lpg`
  in the initramfs so the disk unlock prompt reaches the panel, and installs the Surface Pro 11
  packages (`microsoft-surface-pro-11-support`, `iptsd`, `microsoft-surface-pro-11-sensors`).
- **omarchy-pkgs #2378, #2379, #2382**, by the same author: the sensors and support packages act
  on `microsoft,denali`, both models' shared compatible; in the kernel package the LCD tree gained
  its PWM backlight and dropped the cores the X1P-64-100 has fused off, and LCD hwids
  (`x1p64100-microsoft-denali.json`) came with it, so systemd-stub can pick the LCD tree by the
  panel's EDID.
  Edge carries them today as `linux-omarchy` 7.3-73 and `linux-omarchy-dtbs` 7.3-52.
- **Tested by the author on an LCD unit:** brightness, ten cores with cpufreq, sound, sleep and the
  disk unlock prompt (PR #18276); Wi-Fi, Bluetooth, speakers and microphones, both cameras, the
  Surface Pro Keyboard's keyboard and touchpad, touch and pen, also after resume (omarchy-pkgs
  #2379). **Not tested there:** a fresh install from the ISO on the LCD model, Flex Keyboard
  Bluetooth pairing, Slim Pen pairing.

Everything this repository used to work around (device tree pin, initramfs modules, the OLED-only
package checks, packages from edge on a stable system, Wi-Fi board data, DSP and GPU firmware) is
now done by the edge installer and its packages. See [What changed](#what-changed-on-2026-11-20).

## What this repository adds

1. **`/sp11-lcd/` on the ISO**, the only change to Omarchy's edge ISO by default:
   - `windows/`: every driver package in this machine's Windows driver store whose INF names
     Surface, Qualcomm or Dolby as its provider (202 packages, 1104 files, 1.3 GB here), with
     `device-facts.json` and a `SHA256SUMS` manifest. See [The Windows archive](#the-windows-archive).
   - `setup.sh`, run once after the first boot: it copies the archive to
     `/var/lib/sp11-lcd/windows` (root only) and runs Omarchy's own
     `surface-pro-11-sensors-extract -d` on it. The light sensor configuration is the one thing
     upstream still reads from Windows (`DriverStore/.../surfacepro_snscfgcrd8380.inf_arm64_*`),
     which a full-disk install erases and BitLocker hides.
   - `camera/setup-camera.sh`, opt-in: makes both cameras usable by V4L2-only apps (Monologue,
     Omarchy's screen recording webcam overlay) through on-demand v4l2loopback relays. See
     [payload/sp11-lcd/camera/README.md](payload/sp11-lcd/camera/README.md).
   - `touchscreen/setup-touchscreen.sh`, opt-in: makes the menu's *Disable Touchscreen* turn
     finger touch off. See [payload/sp11-lcd/touchscreen/README.md](payload/sp11-lcd/touchscreen/README.md).
2. **`-LcdOnlyUki`, off by default:** rebuilds the live UKI with only the LCD tree, for the case
   that the Surface firmware does not hand systemd-stub the panel's EDID. See
   [If the live session runs the OLED tree](#if-the-live-session-runs-the-oled-tree).
3. **[contrib/](contrib/README.md):** what is still worth sending upstream.

The kernel, packages and installer are Omarchy's own. Nothing is rebuilt and nothing is installed
from elsewhere, except by the opt-in camera setup: it builds `v4l2-relayd-sp11` (the AUR's
`v4l2-relayd` with one patch) on the installed system.

## Before you wipe Windows

No script can do these for you:

- **Finish Windows Update and every Surface firmware update.** Surface firmware (UEFI, and the
  touch, pen and keyboard firmware) comes through Windows Update; Omarchy offers no way to update the
  Surface UEFI.
- **Make a Surface Recovery Image USB** from <https://support.microsoft.com/surface-recovery-image>
  (needs the serial number, on the kickstand or in *Settings > System > About*). It is the way back
  to Windows, and to firmware updates.
- **Back up your personal data** and save the **BitLocker recovery key**
  (<https://aka.ms/myrecoverykey>).
- **Build the ISO while Windows is still there** (below): the archive is copied from this Windows
  installation.
- **Keep one more copy off the machine.** After the install, the USB stick and
  `/var/lib/sp11-lcd/windows` are the only copies of these files. Copy the ISO, or the staged
  `%USERPROFILE%\sp11-omarchy-build\payload\sp11-lcd` folder, to another disk or your own cloud
  storage. It holds Microsoft, Qualcomm and Dolby files for this device: keep it private.

## Installation

### 1. Build the ISO (on this Surface, in Windows)

With Docker Desktop running:

```powershell
powershell -ExecutionPolicy Bypass -File .\build-iso.ps1
```

- The base is the official edge nightly named in
  <https://nightly.omarchy.org/edge-aarch64/latest.json> (8.5 GB, downloaded once into
  `%USERPROFILE%\sp11-omarchy-build\dl`). The script checks its size and SHA256 against
  `latest.json` and the `.sha256` file. **Edge ISOs carry no release signature**: the checksum
  proves an intact download from Omarchy's server, not who built it. To use an ISO you built
  yourself with [build/edge/build-edge-iso.sh](build/edge/build-edge-iso.sh), pass `-Iso <path>`.
- The result is `%USERPROFILE%\sp11-omarchy-build\out\<base name>-sp11-lcd.iso` (about 9.9 GB),
  with `.sha256` and `.provenance.txt` (base version, `iso_commit`, `omarchy_version`, kernel,
  checksums) next to it. In all it needs about 20 GB (the 8.5 GB download, the 1.3 GB archive and
  the result), and the script stops before it would leave less than 8 GB free.
- At the end it checks that the volume UUID, dates, boot records, GRUB menu and live UKI are the
  base ISO's and that `/sp11-lcd` matches what was staged, file for file.

### 2. Write it to a USB stick

At least 16 GB. Use the ARM64 build of [Rufus](https://rufus.ie) in **DD image mode**. Don't use
Ventoy: the ISO boots through GRUB and a UKI and finds itself by its volume UUID.

### 3. Trial boot (recommended, before anything irreversible)

1. In an admin PowerShell: `Suspend-BitLocker -MountPoint 'C:' -RebootCount 0`, so Windows does
   not ask for the recovery key after Secure Boot is turned off.
2. Surface off, hold **Volume Up + Power** for the UEFI. Set *Security > Secure Boot* to
   **Disabled**. Start from USB with **Volume Down + Power**, or move USB to the top of
   *Boot configuration*.
3. GRUB picks the "device tree" entry on a Snapdragon by itself; a minute or more of black screen
   is normal. The live session opens Omarchy's installer directly. Don't install yet.
4. **Ctrl+Alt+F2** opens a console; log in as `root` (no password). Check:
   ```
   tr -d '\0' </proc/device-tree/model; echo   # Microsoft Surface Pro 11th Edition (LCD)
   cat /sys/devices/soc0/soc_id                 # 615
   cd /run/archiso/bootmnt/sp11-lcd/windows && sha256sum --quiet -c SHA256SUMS && echo archive ok
   ```
   The last line proves the archive on this stick is readable and complete while Windows still
   exists (`findmnt -n -o TARGET /run/archiso/bootmnt` shows the medium if the path differs).
   Also check the picture, the keyboard and the touchpad. If the model says "(OLED)", see
   [below](#if-the-live-session-runs-the-oled-tree).
5. Back in Windows: `Resume-BitLocker -MountPoint 'C:'`.

### 4. Install

- **Full-disk install** (erases Windows): pick the whole disk in the installer. Omarchy's Surface
  Pro 11 step then finds no Windows to read the light sensor configuration from; `setup.sh`
  provides it after the first boot.
- **Dual boot:** Omarchy's free-space install needs BitLocker turned off (*Settings > Privacy &
  security > Device encryption*; decryption takes hours) and free space made by shrinking C: in
  *Disk Management*. Omarchy then reads the sensor configuration from Windows itself; `setup.sh`
  is still the way to keep the archive.
- Leave **Secure Boot off**. Keep disk encryption on.

### 5. First boot

Mount the stick and run `setup.sh` once (details in [payload/sp11-lcd/README.md](payload/sp11-lcd/README.md)):

```bash
sudo mount -o ro /dev/disk/by-label/OMARCHY_* /mnt    # lsblk -f shows the label
sudo bash /mnt/sp11-lcd/setup.sh
sudo umount /mnt
```

Then check:

```bash
tr -d '\0' </proc/device-tree/model; echo           # Microsoft Surface Pro 11th Edition (LCD)
cat /sys/devices/soc0/soc_id                         # 615
grep -A2 'BEGIN OMARCHY SURFACE PRO 11' /etc/kernel/uki.conf   # DeviceTree=.../x1p64100-microsoft-denali.dtb
omarchy-channel-current                              # edge
systemctl status surface-pro-11-sensors              # active (light sensor)
wpctl status | grep -A3 Sinks                        # "Internal speakers" is the default sink
bluetoothctl show | grep -E 'Controller|Powered'     # a real address, not 00:00:00:00:00:00
sudo jq .addresses /var/lib/sp11-lcd/windows/device-facts.json   # the addresses Windows used
qcom-firmware-extract --list-missing                 # prints nothing
```

If the model says "(OLED)" or `uki.conf` names `x1e80100-microsoft-denali-oled.dtb`, the installer
did not see socinfo ID 615 (see open issues). PR #18276's migration is written for exactly that
case (not tried here): run
`OMARCHY_PATH=/usr/share/omarchy bash /usr/share/omarchy/migrations/1794228778.sh` as your user (it
asks for sudo, reruns the Surface Pro 11 setup and rebuilds the UKI), then reboot.

For the cameras in V4L2 apps (optional, needs network; [details](payload/sp11-lcd/camera/README.md)):

```bash
sudo mount -o ro /dev/disk/by-label/OMARCHY_* /mnt
sudo bash /mnt/sp11-lcd/camera/setup-camera.sh       # from your own account, not a root shell
sudo umount /mnt
```

For a working *Disable Touchscreen* trigger (optional; as your own user, without sudo;
[details](payload/sp11-lcd/touchscreen/README.md)):

```bash
sudo mount -o ro /dev/disk/by-label/OMARCHY_* /mnt
bash /mnt/sp11-lcd/touchscreen/setup-touchscreen.sh
sudo umount /mnt
```

### The installed system follows the edge channel

The edge ISO installs `omarchy-dev` and Omarchy's edge repositories, so `omarchy-update` brings
edge's daily builds of Omarchy, the kernel and the Surface packages, before they go through a
release: keep the Snapper snapshots Omarchy takes, and read the update output. **Don't switch to
stable** (`omarchy-channel-set stable`) until a stable
release newer than 4.5.0 contains PR #18276 and the packages above: 4.5.0 has no Surface Pro 11
setup at all.

## If the live session runs the OLED tree

The live UKI carries every Snapdragon tree as `.dtbauto` and systemd's `.hwids`. systemd-stub
picks the LCD tree only through the three CHIDs that include the panel's EDID ID (`LGD077b`); the
SMBIOS-only CHIDs, which the OLED, LCD and 5G models share, pick `microsoft,denali-oled` (the
[tests](#tests) compute both cases). Whether the Surface firmware gives the stub the EDID is
**not verified yet**. If it does not, the live session runs the OLED tree. PR #18276 describes what
that does on this model: the LG panel runs under the Samsung OLED panel driver, whose brightness
control it ignores, and six of the ten cores get no cpufreq. Its author's LCD unit was installed
that way before the fix, which suggests the panel still lights up and the installer stays usable
(an inference; not tried here). The installed system does not depend on it: the installer pins the
tree by socinfo ID.

If the panel stays dark, or to run the live session on the LCD tree anyway, build the fallback. It
rebuilds the live UKI from Omarchy's own kernel, initrd and stub with the LCD tree as its only,
unconditional `.dtb`, the approach that reached the installer on 2026-11-08:

```powershell
powershell -ExecutionPolicy Bypass -File .\build-iso.ps1 -LcdOnlyUki
```

## Known open issues

- **Cameras in V4L2 apps:** Monologue and the screen recording webcam overlay find no camera, since
  both cameras work through libcamera and PipeWire only
  ([omarchy-pkgs #3105](https://github.com/omacom/omarchy-pkgs/issues/3105)). The opt-in
  [camera/setup-camera.sh](payload/sp11-lcd/camera/README.md) works around it. The picture is
  still dim and slightly green under libcamera's simple IPA.
- **Disable Touchscreen does nothing:** Omarchy turns off the raw SPI touchscreen, but finger touch
  comes through iptsd's virtual touchscreen. The opt-in
  [touchscreen/setup-touchscreen.sh](payload/sp11-lcd/touchscreen/README.md) works around it.
- **Right speaker:** the second WSA884x amplifier faults during playback
  ([omarchy #18383](https://github.com/omacom/omarchy/issues/18383)).
- **Flex Keyboard Bluetooth pairing and Slim Pen pairing** are untested upstream on the LCD model.
- **KVM and hibernation** are not available on this machine.
- **Direct Boot** was removed upstream. *Reset Computer* is now *Remove > Factory Reset*: it swaps
  the root subvolume for the install-time snapshot and recreates `/home`, so
  `/var/lib/sp11-lcd` and the sensor configuration are gone afterwards. Run `setup.sh` again from
  the stick or your other copy.
- **socinfo at install time:** the installer pins the LCD tree only if `/sys/devices/soc0/soc_id`
  reads 615 while it runs (socinfo is a module); without it the OLED tree is pinned. Not verified
  on a fresh install; the first-boot checks above detect it.
- **Wi-Fi board data:** see [contrib/README.md](contrib/README.md#2-linux-firmware-has-an-exact-wi-fi-board-record-now).

## The Windows archive

`build-iso.ps1` copies, without administrator rights, every package in
`C:\Windows\System32\DriverStore\FileRepository` whose INF `[Version]` names Surface, Qualcomm or
Dolby as its provider. On this machine that is 202 packages, 1104 files, 1.3 GB. Taking them all is
simpler and safer than guessing which ones Linux tooling will read. It includes:

| What | Driver packages | Read on Linux by |
|---|---|---|
| Light sensor configuration | `surfacepro_snscfgcrd8380` | `surface-pro-11-sensors-extract` (today) |
| ADSP, CDSP, GPU and video firmware, battery manager config | `surfacepro_ext_adsp8380`, `qcnspmcdm_ext_cdsp8380`, `qcdx8380` (`qcvss8380.mbn`, `qcdxkmsuc8380.mbn`) | `qcom-firmware-extract -d` (Omarchy's firmware package carries the same files, see [Tests](#tests)) |
| Dolby speaker tuning (`AUCD_DEV_0C29_SUBSYS_MSHW0486_REV_0D_ADCM_SUBSYS_MSHW0486.xml`) | `dax3_ext_qc` | `/usr/lib/surface-pro-11-support/dolby2pipewire.py`, which the speaker limiter was generated from |
| Camera sensor and ISP tuning | `surfacecam*8380`, `qccam*8380` | nothing yet; front camera colour work (omarchy-pkgs #3105) |
| Wi-Fi board data (`bdwlan*`, `regdb.bin`), Bluetooth firmware and NVM | `qcwlanhmt8380`, `qcbluetooth8380` | nothing yet; this Surface's own calibration, for a future board-2.bin entry |
| Touch, pen, keyboard, UEFI, SAM and retimer firmware | `surfacetouchpen*`, `surfacetypecover*`, `surface_uefi*`, `surfacesam`, `surfaceretimer*` | nothing; kept for the record |

`device-facts.json` records the SMBIOS fields, firmware component versions, SoC, the panel's EDID ID
(`LGD077b`), Wi-Fi, Bluetooth and audio IDs (`AUCD\VEN_QCOM&DEV_0C29&SUBSYS_MSHW0486&REV_0D`), the
Wi-Fi and Bluetooth addresses Windows used, and the `MacAddressEmulationAddress` they imply
(Wi-Fi + 2 = Bluetooth + 1, the layout `microsoft-surface-snapdragon-addresses` reads; the UEFI
variable itself needs administrator rights to read on Windows). It holds no recovery key, product
key, serial number or account data. `SHA256SUMS` lists every file.

## How it works

| File | Role |
|---|---|
| `build-iso.ps1` | Windows side: gets the edge ISO (nightly, checked against `latest.json`, or `-Iso`), stages `sp11-lcd/` with the driver archive and device facts, runs the remaster, writes provenance |
| `build/Dockerfile` | Debian toolbox for the remaster (xorriso, ukify, squashfs-tools) |
| `build/remaster.sh` | Adds `/sp11-lcd` keeping the volume UUID, dates and boot records; with `LCD_ONLY_UKI=1` rebuilds the live UKI on `systemd-stub-omarchy` with only the LCD tree (all GRUB entries chainload that one file, 256 MiB limit); verifies everything it changed and did not change |
| `build/uki-dtb.py` | Splits UKI sections and checks which tree a UKI boots |
| `build/edge/build-edge-iso.sh` | Builds the edge ISO locally with omarchy-iso's own `omarchy-iso-make --arch aarch64 --edge` |
| `build/edge/verify-edge-iso.sh` | Checks, without booting, what an edge ISO carries for the LCD model: GRUB, `.dtbauto` and `.hwids`, initramfs modules, packages, the installer's LCD branch |
| `build/edge/hwids.py` | Reads a UKI's `.hwids` and computes which tree systemd-stub picks, with and without the panel's EDID |
| `build/edge/Dockerfile` | Arch Linux ARM toolbox (omarchy-iso's build image) for the verification and the tests |
| `payload/sp11-lcd/setup.sh`, `README.md` | Go onto the ISO; the post-install step |
| `payload/sp11-lcd/camera/` | Go onto the ISO; the opt-in camera relay: `setup-camera.sh`, the `v4l2-relayd-sp11` PKGBUILD and patch, the user service, v4l2loopback options and a WirePlumber rule |
| `payload/sp11-lcd/touchscreen/` | Go onto the ISO; the opt-in touchscreen toggle: `setup-touchscreen.sh` and `surface-touchscreen` |
| `tools/sp11-chid.ps1` | Computes this machine's systemd CHIDs on Windows and matches them against a hwids JSON |
| `test/edge-test.ps1`, `test/edge-test.sh`, `test/dtb2fs.py` | The container test |
| `contrib/` | Upstream candidates |

## Tests

```powershell
powershell -ExecutionPolicy Bypass -File .\test\edge-test.ps1 -BaseIso <edge ISO> [-Iso <result>]
```

The test mounts both ISOs and the edge target root image (as an overlay; nothing is written to
any of them) in a privileged container and checks:

1. The result boots like the base: volume UUID and dates, El Torito and GPT records, the EFI boot
   partition with GRUB byte for byte, `grub.cfg`, every base file unchanged (with `-LcdOnlyUki`,
   every one but the live UKI), and the medium's own checksums (`omarchy-root.img.zst.sha256`,
   `airootfs.sha512`, `qcom-firmware/SHA256SUMS`).
2. `/sp11-lcd` has every file of the repository's `payload/sp11-lcd/` (`setup.sh`, `README.md`,
   `camera/`, `touchscreen/`), the scripts in `camera/` and `touchscreen/` parse, and `windows/` is
   complete. `setup-camera.sh` and `setup-touchscreen.sh` need a running session and are not run
   in the container; they were run on the Surface (see the
   [camera](payload/sp11-lcd/camera/README.md) and [touchscreen](payload/sp11-lcd/touchscreen/README.md) READMEs).
3. Default build: the live UKI is Omarchy's own and `build/edge/verify-edge-iso.sh` passes on the
   result. Fallback build: `uki-dtb.py check` passes, kernel, initrd, os-release and uname are
   byte-identical to Omarchy's, no `.cmdline` or `.dtbauto`, within 256 MiB.
4. `setup.sh`, run twice from the mounted ISO inside the edge target root image, with the root
   image's own `x1p64100-microsoft-denali.dtb` as the running tree and socinfo ID 615: the archive
   lands root-only and intact in `/var/lib/sp11-lcd/windows`, and the sensor configuration is
   extracted from it. It refuses another machine's tree.
5. Facts stated here: Omarchy's `microsoft-surface-pro-11-firmware` against this machine's driver
   store, file by file; `contrib/`'s CHIDs against Omarchy's and against `device-facts.json`.

Results of 2026-11-20, against `omarchy-2026.11.20-aarch64-edge.iso` (a local build of omarchy-iso
`acf0d36` with omarchy `b20d787`, the commits of nightly 2026.11.20.497): see
[Test results](#test-results) at the end.

## What changed on 2026-11-20

Until 2026-11-19 this repository remastered the signed stable 4.5.0 ISO and fixed the installed
system from the USB before its first boot: an LCD tree pin and a pre.d hook to keep it, initramfs
modules, a pacman hook that rewrote the packages' OLED-only checks, Omarchy's Surface Pro 11
packages fetched from edge onto the USB plus an updater that kept just those five on edge, the
Wi-Fi board record, and DSP/GPU firmware from the driver store. Omarchy's edge channel now does all
of that itself (above), and that "stable plus five edge packages" design no longer works: support
1-9 needs edge's `linux-firmware-qcom` 20261019-1.1. The stable kernel no longer has everything the
LCD model needs either: the LCD tree's PWM backlight and the removal of its fused-off cores are in
`linux-omarchy-dtbs` 7.3-52 on edge. The old scripts are in the git history (commit `5c4807d` and earlier).

## Sources

- [omacom/omarchy](https://github.com/omacom/omarchy) (PR #18276), [omarchy-iso](https://github.com/omacom/omarchy-iso)
  (quattro, `acf0d36`), [omarchy-pkgs](https://github.com/omacom/omarchy-pkgs) (#2378, #2379, #2382)
- [Introducing Omarchy Dragon](https://omarchy.org/news/2026/09/introducing-omarchy-dragon/)
- [qBitnaut/omarchy-dragon-sl7](https://github.com/qBitnaut/omarchy-dragon-sl7): Surface Laptop 7 (X1P-64-100)
- Linux `arch/arm64/boot/dts/qcom/x1p64100-microsoft-denali.dts` (Dale Whinham), systemd `src/boot/{stub,chid,devicetree,edid}.c`

## Test results

2026-11-20, base `omarchy-2026.11.20-aarch64-edge.iso` (SHA256 `3754d075…26878612`), Docker Desktop
on this Surface:

| Build | Result |
|---|---|
| Default: `omarchy-2026.11.20-aarch64-edge-sp11-lcd.iso`, 9,878,634,496 bytes, SHA256 `b111cc9f…20320c175` | 38 checks passed, none failed, one of them `verify-edge-iso.sh` on the result with its own 16 |
| `-LcdOnlyUki`: `omarchy-2026.11.20-aarch64-edge-sp11-lcd-fallback.iso`, 9,854,517,248 bytes (built, tested, then deleted for disk space) | 43 checks passed, none failed (an earlier version of the test, without the EFI partition check); the rebuilt live UKI is 225,617,408 bytes |

What the docs rely on:

- All 11 files of `microsoft-surface-pro-11-firmware` 20261102-3 are byte-identical to this
  machine's driver store copies: `qcadsp8380.mbn`, `adsp_dtb.mbn` (`adsp_dtbs.elf`), `adspr.jsn`,
  `adsps.jsn`, `adspua.jsn`, `battmgr.jsn`, `qccdsp8380.mbn`, `cdsp_dtb.mbn` (`cdsp_dtbs.elf`),
  `cdspr.jsn`, `qcvss8380.mbn`, `qcdxkmsuc8380.mbn`.
- This machine's light sensor files have the hashes `surface-pro-11-sensors-extract` qualified.
- From `device-facts.json`, systemd-stub picks `microsoft,denali-lcd` through CHID EXTRA+2 when it
  has the panel's EDID, and `microsoft,denali-oled` through CHID 3 when it has not.
- The root image's `board-2.bin` (`linux-firmware-atheros` 20261019-1) has an exact
  `subsystem-device=1107`, board-id 255 record for this Wi-Fi card, beside the support package's
  `board.bin` (Qualcomm's 3378/255 reference record).

Not tested: anything on the Surface itself; installing from the ISO; the nightly download (on
2026-11-20 `latest.json` was read, the ISO answered a HEAD request with the size it gives and the
`.sha256` file names the same SHA256, but the 8.5 GB ISO was not downloaded); Omarchy's
`surface-pro-11.sh`, which is checked by reading it, not run.
