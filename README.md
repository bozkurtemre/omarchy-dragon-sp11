# omarchy-dragon-sp11

**English** | [Türkçe](README.tr.md)

A thin layer on top of the official Omarchy aarch64 ISO for installing [Omarchy](https://omarchy.org) 4.5
on the **Microsoft Surface Pro 11, LCD / Snapdragon X Plus (X1P64100)** model.

The official, signed ISO gets exactly two additions:

1. The live UKI boots with the LCD model's device tree.
2. An `sp11-lcd/` fix, run once after installation, makes the installed system boot with the right
   device tree, initramfs and firmware as well.

The kernel, packages and installer are Omarchy's own. Nothing is rebuilt and no foreign packages are added.

> **Status:** the ISO builds and passes its automatic checks, and the `sp11-lcd` fix passes every check
> inside the official ISO's target root image (`test/`). It has not been installed on real hardware
> yet; results will be added here.

## Why is this needed?

Omarchy 4.5.0 officially supports Snapdragon. Its kernel (`linux-omarchy` 7.3) carries many Surface
Pro 11 patches, and the LCD model's device tree (`x1p64100-microsoft-denali.dtb`) is already on the
ISO. Five problems remain on this model:

| Problem | Evidence | What this repo does |
|---|---|---|
| systemd-stub loads the **OLED** device tree on every Surface Pro 11. The OLED, LCD and X Plus models report the same SMBIOS identity, and systemd's `hwids` entry knows only `microsoft,denali-oled`. A matching `.dtbauto` wins over a plain `.dtb` (systemd `src/boot/stub.c`). | `tools/sp11-chid.ps1`: this machine's CHIDs 3, 4, 5, 6, 7, 8, 9 and 10 match the OLED entry, and the stub picks OLED through CHID 3. | Both the live UKI and the installed UKI carry the LCD tree as their only, unconditional `.dtb`. A pre.d hook keeps it that way on every rebuild. |
| 4.5.0 has no Surface Pro 11 setup. The keyboard (`surface_aggregator`, `surface_hid`), display (`msm`, `panel-edp`, eDP PHY) and pmic_glink drivers are all modules, so the disk unlock prompt may have no keyboard or no picture. | `modules.order` on the ISO | Adds Omarchy's Surface Pro 11 module list from the quattro branch to the initramfs, with the LCD's panel driver. |
| DSP/GPU firmware is either missing from the stable repo or extractable only from the Windows partition, which BitLocker makes unreadable. | no `microsoft-surface-pro-11-*` packages in the stable aarch64 repo | Puts this device's signed files from the Windows driver store on the ISO and installs them with Omarchy's own `qcom-firmware-extract -d`. |
| No Wi-Fi: the Surface's WCN7850 reports generic IDs (subsystem `17cb:1107`, board-id 255) that match no `board-2.bin` entry. | Omarchy's `microsoft-surface-pro-11-support` PKGBUILD says so for the Surface Pro 11; the Surface Laptop 7 port hits the same card and ID | Installs Qualcomm's reference-design record as `board.bin`, with the same record, size and SHA256 Omarchy's package uses. ath12k reads it only when `board-2.bin` has no exact match. |
| `ENABLE_UKI`, initramfs and firmware failures can go unnoticed. | the Surface Laptop 7 project's experience | `apply.sh` reads the UKI that will boot, down to its bytes, and reports "safe to reboot" only when that check passes. |

## Verified on this device

| | |
|---|---|
| Model | Surface Pro 11th Edition, SKU `Surface_Pro_11th_Edition_2076`, UEFI 175.449.235 |
| SoC | Snapdragon X Plus 10-core **X1P64100** |
| Internal panel | **LGD077B** (LG LP129WT3 LCD), internal eDP (`0x80000000`); SAM7395 is an external monitor |
| Wi-Fi | Qualcomm WCN7850 (FastConnect 7800), `17cb:1107`, subsystem `17cb:1107` |
| Firmware | SHA256 of `qcadsp8380.mbn`, `adsp_dtbs.elf`, `qccdsp8380.mbn`, `cdsp_dtbs.elf`, `qcdxkmsuc8380.mbn` and `battmgr.jsn` is **identical** to Omarchy's `microsoft-surface-pro-11-firmware` package (Microsoft MSI 26.094.41119.0) |
| Disk | SK hynix UFS 256 GB, GPT, BitLocker **on** |
| ISO | `omarchy-4.5.0-aarch64.iso`: SHA256 and GPG signature verified (Omarchy key `40DF B630 FF42 BCFF B047 046C F013 4EE6 80CA C571`) |

## Installation

### 0. Prepare Windows
- Install every Windows Update and Surface firmware update. The Surface UEFI updates only through Windows.
- Save the **BitLocker recovery key** (<https://aka.ms/myrecoverykey>). Windows will ask for it once
  Secure Boot is turned off.
- **To keep Windows (recommended):**
  1. Turn BitLocker off under *Settings → Privacy & security → Device encryption*. Decryption can
     take hours. Omarchy's "free space" install does not work while BitLocker is on.
  2. Shrink C: in *Disk Management*. 80–120 GB is recommended; 157 GB is free right now.
- Get a **USB-C stick** of at least 16 GB. The ISO is 6.1 GB.

### 0.5 Reconnaissance boot (recommended, before anything irreversible)
Before decrypting BitLocker or shrinking C:, boot the stick once just to the live desktop:
- In an admin PowerShell, run `Suspend-BitLocker -MountPoint 'C:' -RebootCount 0` first, so Windows
  doesn't ask for the recovery key after Secure Boot is turned off. Run `Resume-BitLocker -MountPoint 'C:'`
  when you are back in Windows.
- Follow steps 1–4 below up to the live desktop, without installing. Check the picture, the keyboard and
  the touchpad, and run `tr -d '\0' </proc/device-tree/model` (it should say "(LCD)").
- Wi-Fi, sound and the battery can't be judged here: the live system has no Wi-Fi firmware and keeps
  the DSP off.

### 1. Build the ISO (on this Surface, in Windows)
With Docker Desktop running:

```powershell
powershell -ExecutionPolicy Bypass -File .\build-iso.ps1
```

The result is `%USERPROFILE%\sp11-omarchy-build\out\omarchy-4.5.0-aarch64-sp11-lcd.iso`.
The script verifies the official ISO's signature first. At the end it checks the volume UUID, the
boot records and the LCD-only UKI, and stops if any of them is wrong.

### 2. Write it to the USB stick
Use the ARM64 build of [Rufus](https://rufus.ie) in **DD image mode**. Don't use Ventoy: the ISO
boots through GRUB → UKI and finds itself by its volume UUID.

### 3. Surface UEFI settings
- With the Surface off, hold **Volume Up + Power** to enter the UEFI.
- Set *Security → Secure Boot* to **Disabled**.
- Move USB to the top under *Boot configuration*, or start from USB with **Volume Down + Power**.

### 4. Boot from USB and install
- GRUB detects the Snapdragon and opens the "device tree" entry by itself. 1–3 minutes of black screen is normal.
- Battery percentage and sound don't work in the live session (the DSP is off on purpose). That is not a bug.
- In the installer, pick **Free space install** if you keep Windows. Leave disk encryption on.

### 5. Before rebooting: `sp11-lcd`
When the installer says it is done, **do not reboot**:

```
Ctrl+Alt+F2  →  root (no password)
bash /run/archiso/bootmnt/sp11-lcd/finish-install.sh
```

Enter your disk password. When it prints `It is safe to reboot.`, type `reboot` and pull the USB
stick once the screen goes black. Details are in `payload/sp11-lcd/README.md`.

### 6. Checks on first boot

```bash
tr -d '\0' </proc/device-tree/model; echo        # "Microsoft Surface Pro 11th Edition (LCD)"
sudo dmesg | grep -iE 'remoteproc|ath12k|msm_dpu' | head -30
qcom-firmware-extract --list-missing             # must print nothing
```

If you kept Windows, add it to Limine with `sudo limine-scan`. **Don't** use *Setup → Direct Boot*
on a Surface: the Surface UEFI drops custom EFI boot entries.

## Known gaps and open questions

- **Wi-Fi board data:** `board.bin` is Qualcomm's reference calibration, not this Surface's own, as on
  Omarchy's OLED setup. `sudo dmesg | grep ath12k` shows the board-id the card asks for.
- **Bluetooth:** the WCN7850 stays an unconfigured controller until it is given its public address,
  and Wi-Fi gets a different placeholder MAC on every boot. Omarchy's small
  `microsoft-surface-snapdragon-addresses` package fixes both from the `MacAddressEmulationAddress`
  UEFI variable. It is tested on the Surface Pro 11 and not tied to the OLED model, but it is edge-only
  for now, so it is the first candidate to add.
- **Sound, pen/touch (iptsd), light sensor, Flex keyboard pairing:** Omarchy provides these through
  `microsoft-surface-pro-11-support`, `iptsd` and `microsoft-surface-pro-11-sensors`. For now those
  packages are only on the **edge** channel, and their services run only on `microsoft,denali-oled`.
  The speaker protection limiter is in that package too. Don't turn sound on with random UCM
  settings; the speakers can be damaged.
- Boot entries of Snapper snapshots taken before the fix may start the old UKI, and with it the OLED tree.
- *Setup → Reset Computer* restores the installer's baseline snapshot, which predates the fix: rerun
  `apply.sh` from the USB stick afterwards.

## How it works

| File | Role |
|---|---|
| `build-iso.ps1` | Windows side: downloads the ISO, stages sp11-lcd and the firmware from the driver store, runs the container |
| `build/Dockerfile` | arm64 Debian toolbox (ukify, xorriso, squashfs-tools, gnupg) |
| `build/remaster.sh` | Verifies the signature. Rebuilds the live UKI from its own kernel and initrd and the live system's systemd-stub (262.1), with the LCD tree as its only `.dtb`. Repacks the ISO with the volume dates and UUID kept, then verifies every step |
| `build/uki-dtb.py` | Splits UKI sections and answers "which tree does this UKI boot" (no dependencies; also used on the ISO and the installed system) |
| `payload/sp11-lcd/finish-install.sh` | From the live USB: unlocks and mounts the installed system, runs `apply.sh` in a chroot |
| `payload/sp11-lcd/apply.sh` | Device check (is the panel EDID LGD), tree pin, initramfs, firmware, Wi-Fi board data, rebuild, UKI verification, firmware boot order |
| `payload/sp11-lcd/extract-ath12k-board.py` | Unmodified copy of Omarchy's MIT-licensed board record extractor |
| `payload/sp11-lcd/sp11-lcd-devicetree` | `/etc/boot/hooks/pre.d/90-…`: pins the LCD tree in `uki.conf` before every UKI build |
| `payload/sp11-lcd/zz-sp11-lcd.conf` | initramfs modules (only those the kernel has, without `?`) |
| `tools/sp11-chid.ps1` | Computes this device's systemd CHIDs and shows which tree would be picked |
| `test/chroot-test.ps1`, `test/chroot-test.sh` | Run after `build-iso.ps1`: applies the staged fix inside the official target root image (copy-on-write) and checks the tree pin, the initramfs built for the target kernel, firmware installation against the LCD device tree, the Wi-Fi board record, and the UKI built the way `limine-mkinitcpio` builds it |
| `test/fstab-test.sh` | Unit test of `finish-install.sh`'s fstab handling, for the Omarchy ISO's and genfstab's fstab formats |

## Upstream candidates
- **systemd:** `x1p64100-microsoft-denali.json` (`microsoft,denali-lcd`). The EDID panel CHIDs
  (LGD077B) have higher priority, so the LCD model could be told apart automatically.
- **Omarchy:** `denali-lcd` support in `install/hardware/microsoft/surface-pro-11.sh` (LCD tree and `panel-edp`).
- **omarchy-pkgs:** `microsoft-surface-pro-11-support` should check `microsoft,denali`, not `microsoft,denali-oled`.

## Sources
- [omacom/omarchy](https://github.com/omacom/omarchy) (v4.5.0 and the quattro branch), [omarchy-iso](https://github.com/omacom/omarchy-iso), [omarchy-pkgs](https://github.com/omacom/omarchy-pkgs)
- [Introducing Omarchy Dragon](https://omarchy.org/news/2026/09/introducing-omarchy-dragon/)
- [qBitnaut/omarchy-dragon-sl7](https://github.com/qBitnaut/omarchy-dragon-sl7): Surface Laptop 7 (X1P-64-100); initramfs and "upstream hazards" list
- [harrisonvanderbyl/surface-pro-12-inch-linux](https://github.com/harrisonvanderbyl/surface-pro-12-inch-linux), [bprendie/omarchy-snapdragon](https://github.com/bprendie/omarchy-snapdragon), [javon27/omarchy-surface-touch](https://github.com/javon27/omarchy-surface-touch)
- Linux `arch/arm64/boot/dts/qcom/x1p64100-microsoft-denali.dts` (Dale Whinham), systemd `src/boot/{stub,pe,chid,devicetree}.c`
