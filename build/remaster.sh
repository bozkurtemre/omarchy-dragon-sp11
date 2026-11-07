#!/usr/bin/env bash
# Remaster the official Omarchy aarch64 ISO for the Surface Pro 11 LCD
# (Snapdragon X Plus X1P64100, device tree microsoft,denali-lcd).
#
# Runs inside the build container (see Dockerfile):
#   /in       official ISO + .sha256 + .sig (read-only)
#   /payload  sp11-lcd/ directory to place at the ISO root (read-only)
#   /build    this directory (read-only)
#   /out      result
#   /work     scratch (a Docker volume, so the 6 GB of I/O stays on ext4)
#
# Two changes, nothing else:
#  1. The live UKI boots the LCD tree. The stock one carries every Snapdragon
#     tree as .dtbauto plus systemd's .hwids, and those map every Surface Pro 11
#     to microsoft,denali-oled (the OLED, LCD and X Plus models share SMBIOS
#     IDs). It is rebuilt from its own kernel, initrd, os-release and the live
#     system's own systemd-stub, with the LCD tree from its own .dtbauto set as
#     the only, unconditional .dtb.
#  2. /sp11-lcd holds the post-install fix (README.md) and this machine's
#     signed DSP/GPU firmware.
# The volume dates are kept: archiso finds its medium by the UUID GRUB passes
# (archisosearchuuid=), which is the ISO's modification date.
set -euo pipefail

version=${OMARCHY_VERSION:-4.5.0}
iso=/in/omarchy-$version-aarch64.iso
out=/out/omarchy-$version-aarch64-sp11-lcd.iso
release_key=40DFB630FF42BCFFB047046CF0134EE680CAC571 # manual/48-security.md
compat=microsoft,denali-lcd
uki_path=/arch/boot/aarch64/omarchy-live.efi
work=/work/remaster

die() { echo "remaster: $*" >&2; exit 1; }
step() { echo; echo "==> $*"; }

[[ -f $iso ]] || die "$iso not found"
[[ -f /payload/sp11-lcd/finish-install.sh ]] || die "/payload/sp11-lcd is not staged"
if grep -rlI $'\r' /payload/sp11-lcd --include='*.sh' --include='*.conf' --include='*.py' --include=sp11-lcd-devicetree; then
  die "the files above have Windows line endings; bash would fail on them"
fi
rm -rf "$work" && mkdir -p "$work/sections" "$work/stub"
cd "$work"

step "Verifying the official ISO"
(cd /in && sha256sum -c "omarchy-$version-aarch64.iso.sha256")
export GNUPGHOME=$work/gnupg
mkdir -m 700 "$GNUPGHOME"
curl -fsSL "https://keys.openpgp.org/vks/v1/by-fingerprint/$release_key" | gpg --batch --quiet --import
gpg --batch --status-fd 1 --verify "$iso.sig" "$iso" 2>/dev/null | grep -q "VALIDSIG $release_key" ||
  die "signature on $iso is not from the Omarchy release key $release_key"
echo "Signature: good, Omarchy release key $release_key"

pvd() { xorriso -indev "$1" -pvd_info 2>/dev/null | sed -n "s/^$2 *: //p"; }
ctime=$(pvd "$iso" "Creation Time")
mtime=$(pvd "$iso" "Modif. Time")
[[ $mtime =~ ^[0-9]{16}$ && $ctime =~ ^[0-9]{16}$ ]] || die "cannot read the volume dates ($ctime / $mtime)"
uuid="${mtime:0:4}-${mtime:4:2}-${mtime:6:2}-${mtime:8:2}-${mtime:10:2}-${mtime:12:2}-${mtime:14:2}"
echo "Volume UUID: $uuid"

step "Extracting the live UKI and the live system's systemd-stub"
xorriso -osirrox on -indev "$iso" \
  -extract "$uki_path" live.efi \
  -extract /boot/grub/grub.cfg grub.cfg \
  -extract /arch/aarch64/airootfs.sfs airootfs.sfs >/dev/null 2>&1
grep -q "chainloader $uki_path .*archisosearchuuid=$uuid" grub.cfg ||
  die "grub.cfg does not chainload $uki_path with archisosearchuuid=$uuid; layout changed, review before remastering"
unsquashfs -q -f -d stub airootfs.sfs usr/lib/systemd/boot/efi/linuxaa64.efi.stub
stub=stub/usr/lib/systemd/boot/efi/linuxaa64.efi.stub
[[ -s $stub ]] || die "no linuxaa64.efi.stub in airootfs"
rm -f airootfs.sfs

step "Selecting the $compat device tree"
python3 /build/uki-dtb.py split live.efi sections >dtbs.txt
mapfile -t lcd < <(awk -F'\t' -v c="$compat" '$2 == c { print $1 }' dtbs.txt)
((${#lcd[@]} == 1)) || die "expected one $compat tree in the live UKI, found ${#lcd[@]}"
echo "Using ${lcd[0]} of $(wc -l <dtbs.txt) trees"
for s in .linux .initrd .osrel .uname; do [[ -s sections/$s ]] || die "live UKI has no $s section"; done

step "Building the live UKI"
ukify build \
  --stub="$stub" \
  --linux=sections/.linux \
  --initrd=sections/.initrd \
  --devicetree="sections/${lcd[0]}" \
  --os-release=@sections/.osrel \
  --uname="$(cat sections/.uname)" \
  --output=live-sp11-lcd.efi
python3 /build/uki-dtb.py check live-sp11-lcd.efi "$compat"
python3 /build/uki-dtb.py split live-sp11-lcd.efi rebuilt >/dev/null
for s in .linux .initrd .osrel .uname; do
  cmp -s "sections/$s" "rebuilt/$s" || die "$s changed while rebuilding the UKI"
done
echo "Kernel, initrd, os-release and uname are byte-identical to the official UKI"

step "Writing $(basename "$out")"
rm -f "$out"
xorriso -indev "$iso" -outdev "$out" \
  -volume_date c "$ctime" -volume_date m "$mtime" -volume_date uuid "$mtime" \
  -map live-sp11-lcd.efi "$uki_path" \
  -map /payload/sp11-lcd /sp11-lcd \
  -boot_image any replay \
  -boot_image any gpt_disk_guid=volume_date_uuid \
  -commit 2>&1 | grep -vE '^(xorriso : (NOTE|UPDATE)|libisofs: NOTE|Drive current|Media current|Media status|Media summary|Volume id|Boot record|Writing to|Added to ISO image|Written to medium|xorriso : WARNING : -volume_date uuid)' || true

step "Verifying the result"
[[ $(pvd "$out" "Creation Time") == "$ctime" && $(pvd "$out" "Modif. Time") == "$mtime" ]] ||
  die "volume dates changed; archiso would not find its medium"
[[ $(blkid -o value -s UUID "$out") == "$uuid" ]] || die "volume UUID is not $uuid"
xorriso -osirrox on -indev "$out" -extract "$uki_path" check.efi -extract /sp11-lcd/finish-install.sh check.sh >/dev/null 2>&1
cmp -s check.efi live-sp11-lcd.efi || die "the ISO does not carry the rebuilt UKI"
cmp -s check.sh /payload/sp11-lcd/finish-install.sh || die "the ISO does not carry /sp11-lcd"
report() { xorriso -indev "$1" -report_el_torito plain -report_system_area plain 2>/dev/null | grep -vE '^(Drive|Media|Boot record|Volume id|xorriso)'; }
# Boot records keep their kind and order and the GPT GUIDs (derived from the
# volume date) stay the same; only block addresses and sizes may move.
normalize() { sed -E '/GUID/!s/[0-9]+/N/g'; }
diff <(report "$iso" | normalize) <(report "$out" | normalize) ||
  die "El Torito / partition table layout differs from the official ISO"
echo "UUID $uuid, volume dates, boot records and partition layout match the official ISO"

(cd /out && sha256sum "$(basename "$out")" >"$(basename "$out").sha256")
echo
echo "Done: $out"
cat "$out.sha256"
