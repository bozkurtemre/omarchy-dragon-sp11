#!/usr/bin/env bash
# Add /sp11-lcd to an Omarchy aarch64 edge ISO for the Surface Pro 11 LCD
# (Snapdragon X Plus X1P64100, device tree microsoft,denali-lcd).
#
# Runs inside the build container (see Dockerfile), started by build-iso.ps1:
#   /in       the base ISO, named by BASE_ISO (read-only)
#   /payload  sp11-lcd/ to place at the ISO root (read-only)
#   /build    this directory (read-only)
#   /out      the result, named by OUT_ISO, with .sha256 and .provenance.txt
#   /work     scratch (a Docker volume)
#
# By default /sp11-lcd is the only change. Omarchy's live UKI carries every
# Snapdragon tree as .dtbauto plus systemd's .hwids, and systemd-stub picks the
# LCD tree through the panel's EDID CHIDs, but only if the firmware hands the
# stub the EDID; otherwise the SMBIOS CHIDs pick microsoft,denali-oled.
# LCD_ONLY_UKI=1 is for that case: the live UKI is rebuilt from its own kernel,
# initrd, os-release and uname, on the stub Omarchy builds it with
# (systemd-stub-omarchy, from the live root), with the LCD tree from its own
# .dtbauto set as the only, unconditional .dtb.
#
# The volume dates are kept: archiso finds its medium by the UUID GRUB passes
# (archisosearchuuid=), which is the ISO's modification date, and the GPT
# GUIDs are derived from it.
set -euo pipefail

iso=/in/${BASE_ISO:?BASE_ISO names the base ISO in /in}
out=/out/${OUT_ISO:?OUT_ISO names the result in /out}
lcd_only=${LCD_ONLY_UKI:-0}
payload=/payload/sp11-lcd
compat=microsoft,denali-lcd
uki_path=/arch/boot/aarch64/omarchy-live.efi
stub_path=usr/lib/systemd-stub-omarchy/linuxaa64.efi.stub # omarchy-iso builder/qualcomm/live-uki.sh
uki_limit=$((256 * 1024 * 1024))                          # ditto: GRUB must place the whole UKI in memory
work=/work/remaster

die() { echo "remaster: $*" >&2; exit 1; }
step() { echo; echo "==> $*"; }

[[ -f $iso ]] || die "$iso not found"
[[ -f $payload/setup.sh && -f $payload/windows/SHA256SUMS ]] || die "$payload is not staged (run build-iso.ps1)"
# Our own files must have LF endings; the driver archive is Windows' own and stays as it is.
if grep -lI $'\r' "$payload"/*.sh "$payload"/*.md; then
  die "the files above have Windows line endings; bash would fail on them"
fi
rm -rf "$work" && mkdir -p "$work" && cd "$work"

step "Checking the staged archive against its SHA256SUMS"
(cd "$payload/windows" && sha256sum --quiet -c SHA256SUMS) || die "the staged archive does not match its SHA256SUMS"
echo "$(wc -l <"$payload/windows/SHA256SUMS") files, $(du -sh "$payload" | cut -f1)"

step "Reading the base ISO"
pvd() { xorriso -indev "$1" -pvd_info 2>/dev/null | sed -n "s/^$2 *: //p"; }
ctime=$(pvd "$iso" "Creation Time")
mtime=$(pvd "$iso" "Modif. Time")
[[ $mtime =~ ^[0-9]{16}$ && $ctime =~ ^[0-9]{16}$ ]] || die "cannot read the volume dates ($ctime / $mtime)"
uuid="${mtime:0:4}-${mtime:4:2}-${mtime:6:2}-${mtime:8:2}-${mtime:10:2}-${mtime:12:2}-${mtime:14:2}"
echo "Volume $(pvd "$iso" "Volume Id"), UUID $uuid"
xorriso -osirrox on -indev "$iso" -extract /boot/grub/grub.cfg grub.cfg -extract "$uki_path" live.efi >/dev/null 2>&1
[[ -s grub.cfg && -s live.efi ]] || die "the ISO has no /boot/grub/grub.cfg or $uki_path"
# Every entry that chainloads a file of the live system (the device tree entry
# and its speakup twin) must boot this UKI on this volume, or a rebuilt UKI
# would miss one. The UEFI shell entries chainload other files.
mapfile -t chains < <(grep -E '^[[:space:]]*chainloader /arch/' grub.cfg)
((${#chains[@]} > 0)) || die "grub.cfg chainloads nothing under /arch; layout changed, review before remastering"
for line in "${chains[@]}"; do
  [[ $line == *"chainloader $uki_path "*"archisosearchuuid=$uuid "* ]] ||
    die "grub.cfg has '$line', not $uki_path with archisosearchuuid=$uuid; layout changed, review before remastering"
done
echo "${#chains[@]} GRUB entries chainload $uki_path with archisosearchuuid=$uuid"
python3 /build/uki-dtb.py split live.efi sections >dtbs.txt
for s in .linux .initrd .osrel .uname; do [[ -s sections/$s ]] || die "the live UKI has no $s section"; done
echo "Live UKI: $(stat -c %s live.efi) bytes, $(wc -l <dtbs.txt) device trees, kernel $(cat sections/.uname)"
uki=live.efi

if ((lcd_only)); then
  step "Rebuilding the live UKI with only the $compat tree (LCD_ONLY_UKI=1)"
  [[ ! -e sections/.cmdline ]] || die "the live UKI has a .cmdline, which would override GRUB's; review before remastering"
  mapfile -t lcd < <(awk -F'\t' -v c="$compat" '$2 == c { print $1 }' dtbs.txt)
  ((${#lcd[@]} == 1)) || die "expected one $compat tree in the live UKI, found ${#lcd[@]}"
  echo "Using ${lcd[0]} of $(wc -l <dtbs.txt) trees"
  xorriso -osirrox on -indev "$iso" -extract /arch/aarch64/airootfs.sfs airootfs.sfs >/dev/null 2>&1
  unsquashfs -q -f -d stub airootfs.sfs "$stub_path"
  rm -f airootfs.sfs
  [[ -s stub/$stub_path ]] || die "no /$stub_path in the live root"
  ukify build \
    --stub="stub/$stub_path" \
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
  [[ ! -e rebuilt/.cmdline ]] || die "the rebuilt UKI has a .cmdline"
  size=$(stat -c %s live-sp11-lcd.efi)
  ((size <= uki_limit)) || die "the rebuilt UKI is $size bytes, over omarchy-iso's $uki_limit-byte limit"
  echo "Kernel, initrd, os-release and uname are byte-identical to Omarchy's UKI; $size bytes"
  uki=live-sp11-lcd.efi
fi

step "Writing $(basename "$out")"
map_uki=()
[[ $uki == live.efi ]] || map_uki=(-map "$uki" "$uki_path")
rm -f "$out" "$out.sha256"
xorriso -indev "$iso" -outdev "$out" \
  -volume_date c "$ctime" -volume_date m "$mtime" -volume_date uuid "$mtime" \
  "${map_uki[@]}" \
  -map "$payload" /sp11-lcd \
  -boot_image any replay \
  -boot_image any gpt_disk_guid=volume_date_uuid \
  -commit 2>&1 | grep -vE '^(xorriso : (NOTE|UPDATE)|libisofs: NOTE|Drive current|Media current|Media status|Media summary|Volume id|Boot record|Writing to|Added to ISO image|Written to medium|xorriso : WARNING : -volume_date uuid)' || true

step "Verifying the result"
[[ $(pvd "$out" "Creation Time") == "$ctime" && $(pvd "$out" "Modif. Time") == "$mtime" ]] ||
  die "volume dates changed; archiso would not find its medium"
[[ $(blkid -o value -s UUID "$out") == "$uuid" ]] || die "volume UUID is not $uuid"
xorriso -osirrox on -indev "$out" -extract "$uki_path" check.efi -extract /boot/grub/grub.cfg check.cfg >/dev/null 2>&1
cmp -s check.efi "$uki" || die "the ISO does not carry the intended live UKI ($uki)"
cmp -s check.cfg grub.cfg || die "grub.cfg changed"
compare=$(xorriso -indev "$out" -compare_r "$payload" /sp11-lcd 2>&1)
grep -q '^Both file objects match' <<<"$compare" || { grep -E "^- |Differences" <<<"$compare" | head -20; die "/sp11-lcd on the ISO differs from $payload"; }
report() { xorriso -indev "$1" -report_el_torito plain -report_system_area plain 2>/dev/null | grep -vE '^(Drive|Media|Boot record|Volume id|xorriso)'; }
# Boot records keep their kind and order and the GPT GUIDs (derived from the
# volume date) stay the same; only block addresses and sizes may move.
normalize() { sed -E '/GUID/!s/[0-9]+/N/g'; }
diff <(report "$iso" | normalize) <(report "$out" | normalize) ||
  die "El Torito / partition table layout differs from the base ISO"
echo "UUID $uuid, volume dates, boot records, partition layout and grub.cfg match the base ISO"
echo "/sp11-lcd matches the staged payload, file for file; the live UKI is $([[ $uki == live.efi ]] && echo "Omarchy's own" || echo "the rebuilt LCD-only one")"

cd /out
sha256sum "$(basename "$out")" >"$(basename "$out").sha256"
{
  echo "volume     $(pvd "$out" "Volume Id"), UUID $uuid (as the base ISO)"
  echo "live root  $(grep -E '^(BUILD_ID|IMAGE_VERSION)=' "$work/sections/.osrel" | tr '\n' ' ')kernel $(cat "$work/sections/.uname")"
  echo "live UKI   sha256 $(sha256sum "$work/check.efi" | cut -d' ' -f1) ($(stat -c %s "$work/check.efi") bytes)"
  echo "output     sha256 $(cut -d' ' -f1 "$(basename "$out").sha256"), $(stat -c %s "$out") bytes"
} >>"$out.provenance.txt"
rm -rf "$work"
echo
echo "Done: $out"
cat "$out.sha256"
