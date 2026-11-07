#!/bin/bash
# Make an Omarchy 4.5 install boot and run right on the Surface Pro 11 LCD
# (Snapdragon X Plus, device tree microsoft,denali-lcd).
#
# Runs as root inside the installed system: from the live USB through
# finish-install.sh (arch-chroot), or directly on the booted install:
#   sudo bash apply.sh PAYLOAD_DIR [--force]
# PAYLOAD_DIR is the sp11-lcd directory (scripts + firmware/). Safe to rerun.
#
#  1. Pins the LCD device tree in the UKI and keeps it pinned on every rebuild.
#  2. Loads panel, display and keyboard drivers in the initramfs, so the disk
#     unlock prompt is visible and the Surface keyboard types into it.
#  3. Installs Omarchy's Surface Pro 11 packages (sound, touch and pen, light
#     sensor, Bluetooth address, DSP/GPU firmware) from the USB's copy of the
#     edge repository's signed packages, lets them act on the LCD model, and
#     hooks their updates from edge into omarchy-update (sp11-lcd-update).
#  4. Installs this machine's signed DSP/GPU firmware with Omarchy's
#     qcom-firmware-extract where the packages left any missing, and enables
#     the DSP driver once nothing is missing.
#  5. Gives Wi-Fi the board data its unprogrammed WCN7850 finds nowhere else.
#  6. Rebuilds the boot image and checks the UKI that will actually boot.
set -euo pipefail

payload=${1:?usage: apply.sh PAYLOAD_DIR [--force]}
force=${2:-}
compat=microsoft,denali-lcd
lib=/usr/local/lib/sp11-lcd
hook=/etc/boot/hooks/pre.d/90-sp11-lcd-devicetree

die() { echo "sp11-lcd: ERROR: $*" >&2; exit 1; }
warn() { echo "sp11-lcd: WARNING: $*" >&2; }
step() { echo; echo "==> $*"; }

((EUID == 0)) || die "run as root"
[[ $(uname -m) == aarch64 ]] || die "not an aarch64 system"
[[ -d /usr/share/omarchy ]] || die "no Omarchy installation in this root"
for f in sp11-lcd-devicetree zz-sp11-lcd.conf uki-dtb.py extract-ath12k-board.py apply.sh \
  sp11-lcd-ungate 90-sp11-lcd-ungate.hook sp11-lcd-update sp11-lcd-post-update; do
  [[ -f $payload/$f ]] || die "$payload/$f is missing"
done

step "Checking the machine"
product=$(cat /sys/class/dmi/id/product_name 2>/dev/null || true)
if [[ $product != "Microsoft Surface Pro, 11th Edition" && $force != --force ]]; then
  die "this is '${product:-unknown}', not a Surface Pro 11 (--force overrides)"
fi
# The internal panel tells the LCD (LG Display) from the OLED (Samsung) model;
# the running device tree is only a fallback, since it may be the wrong one.
panel=""
for edid in /sys/class/drm/card*-eDP-*/edid; do
  [[ -s $edid ]] || continue
  read -r b8 b9 < <(od -An -tu1 -j8 -N2 "$edid")
  id=$(( (b8 << 8) | b9 ))
  panel=$(printf "\\$(printf %o $(( ((id >> 10) & 31) + 64 )))\\$(printf %o $(( ((id >> 5) & 31) + 64 )))\\$(printf %o $(( (id & 31) + 64 )))")
  break
done
running=$(tr '\0' ' ' </proc/device-tree/compatible 2>/dev/null || true)
if [[ $panel == LGD ]]; then
  echo "Internal panel: LG Display (LCD model)"
elif [[ -n $panel && $force != --force ]]; then
  die "internal panel is '$panel', not the LCD model's LG Display panel; this fix is for the LCD model (--force overrides)"
elif [[ -z $panel && " $running " != *" $compat "* && $force != --force ]]; then
  die "cannot read the panel and the running device tree is '${running:-none}'; boot the sp11-lcd USB first (--force overrides)"
fi

step "Installing the device tree pin"
install -d -m 755 "$lib" "$(dirname "$hook")"
install -m 755 "$payload/sp11-lcd-devicetree" "$payload/apply.sh" "$payload/uki-dtb.py" \
  "$payload/extract-ath12k-board.py" "$payload/sp11-lcd-ungate" "$payload/sp11-lcd-update" \
  "$payload/sp11-lcd-post-update" "$lib/"
install -m 644 "$payload/zz-sp11-lcd.conf" "$lib/"
ln -sfn "$lib/sp11-lcd-devicetree" "$hook"
"$lib/sp11-lcd-devicetree"
pinned=$(sed -n '/^# BEGIN SP11 LCD DEVICE TREE$/,/^# END SP11 LCD DEVICE TREE$/s/^DeviceTree=//p' /etc/kernel/uki.conf)
[[ -n $pinned && -f $pinned ]] || die "the LCD device tree is not pinned in /etc/kernel/uki.conf"
! grep -q '^DeviceTreeAuto=' /etc/kernel/uki.conf || die "/etc/kernel/uki.conf still lists DeviceTreeAuto="
echo "DeviceTree=$pinned"

step "Adding panel, display and keyboard drivers to the initramfs"
install -m 644 "$payload/zz-sp11-lcd.conf" /etc/mkinitcpio.conf.d/zz-sp11-lcd.conf
echo "/etc/mkinitcpio.conf.d/zz-sp11-lcd.conf"

step "Installing Omarchy's Surface Pro 11 packages"
# The pacman hook first, so the packages come out of the transaction already
# acting on the LCD model. The stable channel does not carry these packages,
# so omarchy-update's post-update hook brings them up to edge's versions
# (sp11-lcd-update): per user, and in skel for a user created at first boot
# (deferred provisioning).
install -Dm644 "$payload/90-sp11-lcd-ungate.hook" /etc/pacman.d/hooks/90-sp11-lcd-ungate.hook
for home in /etc/skel /home/*; do
  [[ -d $home ]] || continue
  install -Dm755 "$lib/sp11-lcd-post-update" "$home/.config/omarchy/hooks/post-update.d/sp11-lcd"
  if [[ $home != /etc/skel ]]; then
    chown -R "$(stat -c %u:%g "$home")" "$home/.config/omarchy" 2>/dev/null || true
  fi
done
# The USB's copy: Omarchy's signed packages and their dependencies, resolved
# against this release's image at ISO build time (build/fetch-packages.sh).
# Only what is not installed yet: a rerun must not downgrade what
# sp11-lcd-update brought in since, and a rerun from /usr/local/lib/sp11-lcd
# has no pkgs/ at all.
pkgs=()
for pkg in "$payload"/pkgs/*.pkg.tar.*; do
  [[ -f $pkg && $pkg != *.sig ]] || continue
  name=$(pacman -Qpq "$pkg" 2>/dev/null) || die "$pkg is not a package pacman can read"
  pacman -Q "$name" >/dev/null 2>&1 || pkgs+=("$pkg")
done
if ((${#pkgs[@]})); then
  pacman -U --noconfirm "${pkgs[@]}"
fi
for name in microsoft-surface-pro-11-firmware microsoft-surface-pro-11-support \
  microsoft-surface-pro-11-sensors microsoft-surface-snapdragon-addresses iptsd pipewire-libcamera; do
  pacman -Q "$name" >/dev/null 2>&1 || die "$name is not installed and not on the USB (sp11-lcd/pkgs); rebuild the ISO with build-iso.ps1"
done
"$lib/sp11-lcd-ungate"
left=$(pacman -Qlq microsoft-surface-pro-11-support microsoft-surface-pro-11-sensors | xargs grep -ls 'microsoft,denali-oled' || true)
[[ -z $left ]] || die "still gated on the OLED model: $left"
# Omarchy's own Surface Pro 11 setup enables the sensor service; the Flex
# Keyboard units are started by udev, and iptsd by its own udev rule.
systemctl enable surface-pro-11-sensors.service
if [[ -d $payload/sensors ]]; then
  # The light sensor's configuration, from this machine's Windows driver store
  # (staged by build-iso.ps1). Needs the running device tree to be a Denali.
  surface-pro-11-sensors-extract -d "$payload/sensors" || warn "sensor configuration not extracted; auto brightness stays off until 'sudo surface-pro-11-sensors-extract' is run with Windows readable"
else
  warn "no sensors/ on the USB; auto brightness needs 'sudo surface-pro-11-sensors-extract' with Windows readable"
fi

step "Installing DSP and GPU firmware"
command -v qcom-firmware-extract >/dev/null || die "qcom-firmware-extract is not installed (Omarchy installs it on Snapdragon machines)"
if [[ -d $payload/firmware ]]; then
  # Missing firmware must not stop the device tree and initramfs fixes, which
  # are what the next boot depends on; --list-missing below decides the DSP.
  qcom-firmware-extract --install --no-rebuild -d "$payload/firmware" || warn "qcom-firmware-extract reported a problem (see above)"
else
  warn "no firmware/ in $payload; using whatever is already installed"
fi
missing=$(qcom-firmware-extract --list-missing || true)
nofw=/etc/modprobe.d/qualcomm-adsp-nofw.conf
if [[ -n $missing ]]; then
  warn "firmware still missing, the DSP driver stays off (no audio/battery/USB-C alt mode):"
  echo "$missing" >&2
elif [[ -f $nofw ]] && grep -q 'Generated by Omarchy' "$nofw"; then
  rm -f "$nofw"
  echo "All device-tree firmware present; enabled the DSP driver (removed $nofw)"
else
  echo "All device-tree firmware present"
fi

step "Wi-Fi board data"
# The Surface's WCN7850 reports generic identifiers (subsystem 17cb:1107,
# board-id 255) that match no board-2.bin entry, so ath12k finds no board data
# and Wi-Fi stays down. Install Qualcomm's own reference-design record as
# board.bin, exactly as Omarchy's microsoft-surface-pro-11-support does (record,
# size and checksum from its PKGBUILD); the Surface Laptop 7 port runs the same
# data on the same 17cb:1107 card. ath12k reads board.bin only when board-2.bin
# has no exact match, so a card that reports a listed board-id is unaffected.
board_dir=/usr/lib/firmware/ath12k/WCN7850/hw2.0
board_bin=/usr/lib/firmware/updates/ath12k/WCN7850/hw2.0/board.bin
board_record='bus=pci,vendor=17cb,device=1107,subsystem-vendor=17cb,subsystem-device=3378,qmi-chip-id=2,qmi-board-id=255'
if compgen -G "$board_dir/board.bin*" >/dev/null || [[ -f $board_bin ]]; then
  echo "board.bin already present"
else
  container=$board_dir/board-2.bin
  scratch=$(mktemp -d)
  if [[ ! -f $container && -f $container.zst ]]; then
    zstd -dq "$container.zst" -o "$scratch/board-2.bin" && container=$scratch/board-2.bin
  fi
  if python3 "$payload/extract-ath12k-board.py" --expected-bytes 88872 \
    --expected-sha256 0ef5f6f3cb124f33c6de52371819ccd7c13763ceb86d476a178fd56e4cdc26a3 \
    "$container" "$board_record" "$scratch/board.bin"; then
    install -Dm644 "$scratch/board.bin" "$board_bin"
    echo "Installed $board_bin"
  else
    warn "could not extract the Wi-Fi board record from $container; Wi-Fi may not come up"
  fi
  rm -rf "$scratch"
fi

step "Rebuilding the boot image"
started=$(date +%s)
log=$(mktemp)
trap 'rm -f "$log"' EXIT
limine-mkinitcpio 2>&1 | tee "$log"
# limine-mkinitcpio reports a kernel it could not rebuild and still exits 0.
! grep -q 'mkinitcpio failed for kernel' "$log" || die "the boot image was not rebuilt; see the output above"

step "Checking the UKI that will boot"
esp=$(sed -n 's/^ESP_PATH="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p' /etc/default/limine 2>/dev/null | tail -1)
esp=${esp:-/boot}
fresh=0 bad=0
for uki in "$esp"/EFI/Linux/*.efi; do
  [[ -f $uki ]] || continue
  if (( $(stat -c %Y "$uki") < started )); then
    warn "$uki was not rebuilt now (older snapshot or fallback image); it may boot the wrong device tree"
    continue
  fi
  fresh=$((fresh + 1))
  python3 "$lib/uki-dtb.py" check "$uki" "$compat" || bad=$((bad + 1))
done
((fresh > 0)) || die "no UKI was rebuilt under $esp/EFI/Linux (is ENABLE_UKI=yes? see /etc/limine-entry-tool.d/omarchy-uki.conf)"
((bad == 0)) || die "$bad rebuilt UKI(s) do not boot $compat"

# The Surface UEFI is known to drop or reorder custom boot entries; say what it
# will start, so a reboot straight into Windows is not a mystery.
if efibootmgr >/dev/null 2>&1; then
  first=$(efibootmgr | sed -n 's/^BootOrder: \([0-9A-Fa-f]*\).*/\1/p')
  label=$(efibootmgr | sed -n "s/^Boot$first\*\{0,1\} \([^\t]*\).*/\1/p")
  echo "Firmware boot order starts with: ${label:-unknown} (Boot$first)"
  if [[ $label != *[Ll]imine* ]]; then
    warn "Limine is not first; if the Surface starts Windows, move Limine to the top in UEFI > Boot configuration"
  fi
fi

echo
echo "sp11-lcd: DONE. The installed system boots the Surface Pro 11 LCD device tree."
echo "sp11-lcd: It is safe to reboot."
