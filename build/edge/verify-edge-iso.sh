#!/usr/bin/env bash
# Check, without booting it, what an Omarchy aarch64 ISO carries for the
# Surface Pro 11 LCD (Snapdragon X Plus X1P64100, microsoft,denali-lcd).
#
# Runs in a privileged Arch Linux ARM container (loop mounts of the ISO, its
# live squashfs and the btrfs root image):
#   verify-edge-iso.sh ISO OUTDIR
#   /build    this repository's build/ directory (uki-dtb.py, edge/hwids.py)
# OUTDIR gets report.txt and the evidence it quotes; OUTDIR/work holds the
# unpacked root image and UKI sections (several GB) and can be deleted after.
#
#  1. Volume label and UUID, El Torito and GPT, GRUB's Snapdragon entry
#  2. The live UKI's device trees and .hwids, and what systemd-stub would pick
#  3. Kernel release and display/keyboard modules in both live initramfs images
#  4. Package versions in the offline mirror, the root image and the live root
#  5. The installer's install/hardware/microsoft/surface-pro-11.sh
#  6. What the Surface Pro 11 packages carry, and where the LCD tree's
#     firmware and Wi-Fi board data come from
# test/edge-test.sh runs it on the remastered ISO, which must still carry all
# of this unchanged.
set -uo pipefail

iso=$(readlink -f "${1:?usage: verify-edge-iso.sh ISO OUTDIR}")
out=$(readlink -f "${2:?usage: verify-edge-iso.sh ISO OUTDIR}")
build=${BUILD_DIR:-/build}
compat=microsoft,denali-lcd
panel=LGD077b
lcd_chids=(3ae5702b-a1d9-50d5-83d8-4aa34e371123 dac465e6-ddc3-5777-a3f7-a0ce47d41e1d 26f0f85f-48fb-5d0b-b671-9e70dc8e83d5)
modules=(msm panel-edp pwm_bl leds-qcom-lpg surface_aggregator surface_aggregator_registry surface_aggregator_hub
  surface_hid surface_hid_core spi-hid)
packages=(microsoft-surface-pro-11-support microsoft-surface-pro-11-sensors microsoft-surface-pro-11-firmware
  microsoft-surface-snapdragon-addresses iptsd pipewire-libcamera linux-omarchy linux-omarchy-dtbs
  linux-firmware-qcom linux-firmware-atheros omarchy-dev omarchy omarchy-settings-dev limine-mkinitcpio-hook
  systemd-stub-omarchy systemd qcom-firmware-extract)
spec=usr/share/omarchy/install/hardware/microsoft/surface-pro-11.sh

die() { echo "verify: $*" >&2; exit 1; }
step() { echo; echo "==> $*"; }
fails=0
ok() { echo "PASS: $*"; }
bad() { echo "FAIL: $*"; fails=$((fails + 1)); }

[[ -f $iso ]] || die "$iso not found"
[[ -f $build/uki-dtb.py && -f $build/edge/hwids.py ]] || die "$build lacks uki-dtb.py or edge/hwids.py"
work=$out/work
mnt=$work/mnt
mkdir -p "$work/pkgs" "$mnt/iso" "$mnt/live" "$mnt/root" "$out/hwids-json"
exec > >(tee "$out/report.txt") 2>&1

cleanup() {
  umount "$mnt/root" "$mnt/live" "$mnt/iso" 2>/dev/null
}
trap cleanup EXIT
mount -o loop,ro "$iso" "$mnt/iso" || die "cannot mount $iso"
mount -o loop,ro -t squashfs "$mnt/iso/arch/aarch64/airootfs.sfs" "$mnt/live" || die "cannot mount airootfs.sfs"
# An unpacked root image from an earlier run is reused only if it came from
# this ISO's omarchy-root.img.zst (root.img.sha256 records which one).
zst_sum=$(awk '$2 == "omarchy-root.img.zst" { print $1 }' "$mnt/iso/arch/aarch64/omarchy-root.img.zst.sha256")
if [[ ! -s $work/root.img || $(cat "$work/root.img.sha256" 2>/dev/null) != "$zst_sum" ]]; then
  rm -f "$work/root.img" "$work/root.img.sha256"
  zstd -dq "$mnt/iso/arch/aarch64/omarchy-root.img.zst" -o "$work/root.img.part" && mv "$work/root.img.part" "$work/root.img" &&
    echo "$zst_sum" >"$work/root.img.sha256"
fi
mount -o loop,ro "$work/root.img" "$mnt/root" || die "cannot mount the root image"
root=$mnt/root/omarchy-root
live=$mnt/live
[[ -d $root/usr/share/omarchy ]] || die "no Omarchy runtime in the root image"

# name<TAB>version<TAB>filename of every package in a sync db
db_index() {
  bsdtar -xOf "$1" --include='*/desc' |
    awk '/^%FILENAME%$/ { getline f } /^%NAME%$/ { getline n } /^%VERSION%$/ { getline v; print n "\t" v "\t" f }'
}
# name<TAB>version of every package in a local db
local_index() {
  local desc
  for desc in "$1"/var/lib/pacman/local/*/desc; do
    awk '/^%NAME%$/ { getline n } /^%VERSION%$/ { getline v; print n "\t" v }' "$desc"
  done
}
# The local package that owns a path (relative to the root)
owner() { grep -lx "$2" "$1"/var/lib/pacman/local/*/files 2>/dev/null | awk -F/ '{ print $(NF-1) }'; }

step "1. ISO volume, boot records, GRUB"
echo "file: $iso"
stat -c 'size: %s bytes' "$iso"
sha256sum "$iso" | sed 's/^/sha256: /'
xorriso -indev "$iso" -pvd_info 2>/dev/null | grep -E '^(Volume Id|Volume Set Id|Publisher Id|App Id|Creation Time|Modif. Time)'
blkid -p -o export "$iso" | grep -E '^(UUID|LABEL|TYPE|PTTYPE|PTUUID)='
uuid=$(blkid -p -o value -s UUID "$iso")
xorriso -indev "$iso" -report_el_torito plain -report_system_area plain 2>/dev/null | grep -vE '^(Drive|Media|xorriso :)'
grub_cfg=$mnt/iso/boot/grub/grub.cfg
[[ -f $grub_cfg ]] || grub_cfg=$(find "$mnt/iso" -name grub.cfg -print -quit)
cp "$grub_cfg" "$out/grub.cfg"
echo "grub.cfg: ${grub_cfg#"$mnt/iso"}"
uki_entry=$(awk "/--id 'archlinux-uki'/,/^    }/" "$grub_cfg")
grep -nE "regexp '(Qualcomm|Snapdragon)'|default=archlinux-uki" "$grub_cfg"
echo "$uki_entry"
chain=$(sed -n 's/^ *chainloader \([^ ]*\) .*/\1/p' <<<"$uki_entry" | head -1)
if [[ -n $chain && -f $mnt/iso$chain ]]; then ok "the device tree entry chainloads $chain, which is on the ISO"; else bad "no chainloaded UKI ($chain)"; fi
if grep -q "archisosearchuuid=$uuid " <<<"$uki_entry"; then ok "archisosearchuuid matches the volume UUID $uuid"; else bad "archisosearchuuid is not $uuid"; fi

step "2. Live UKI device trees and .hwids"
cp "$mnt/iso$chain" "$work/live.efi"
rm -rf "$work/sections"
python3 "$build/uki-dtb.py" split "$work/live.efi" "$work/sections" >"$out/dtbauto.txt"
echo "sections: $(find "$work/sections" -maxdepth 1 -type f ! -name '.dtbauto.*' -printf '%f ' | tr ' ' '\n' | sort | tr '\n' ' ')"
echo "$(grep -c . "$out/dtbauto.txt") .dtbauto device trees; the Denali ones:"
grep -E 'denali' "$out/dtbauto.txt"
mapfile -t lcd < <(awk -F'\t' -v c="$compat" '$2 == c { print $1 }' "$out/dtbauto.txt")
if ((${#lcd[@]} == 1)); then ok "one .dtbauto tree has first compatible $compat (${lcd[0]})"; else bad "${#lcd[@]} trees have first compatible $compat"; fi
echo ".uname: $(cat "$work/sections/.uname")"
echo ".osrel: $(grep -E '^(NAME|BUILD_ID|VERSION_ID|IMAGE_VERSION)=' "$work/sections/.osrel" | tr '\n' ' ')"
echo ".sbat:"; tr -d '\0' <"$work/sections/.sbat" | sed 's/^/  /'
python3 "$build/edge/hwids.py" dump "$work/sections/.hwids" >"$out/hwids.txt"
echo "$(grep -c . "$out/hwids.txt") .hwids records; the Denali ones:"
grep -E 'denali' "$out/hwids.txt"
for g in "${lcd_chids[@]}"; do
  if grep -qP "^devicetree\t$g\t.*\t$compat$" "$out/hwids.txt"; then ok "$g maps to $compat"; else bad "$g does not map to $compat"; fi
done
hwdir=$live/usr/lib/systemd/boot/hwids/aa64
if python3 "$build/edge/hwids.py" compare "$work/sections/.hwids" "$hwdir"; then
  ok "the parsed section reproduces the live root's $(find "$hwdir" -name '*.json' | wc -l) hwids JSON files exactly"
else
  bad "the parsed section differs from the live root's hwids JSON files"
fi
while IFS= read -r json; do
  cp "$json" "$out/hwids-json/"
  echo "${json#"$hwdir/"}: owned by $(owner "$live" "${json#"$live/"}")"
done < <(find "$hwdir" -name '*denali*.json' | sort)
# The EXTRA CHIDs exist only if the stub reads the panel's EDID from the firmware.
edid=$(grep -aoE 'edid_get_discovered_panel_id|src/boot/edid\.c' "$work/sections/.rodata" | sort -u | tr '\n' ' ')
if [[ -n $edid ]]; then ok "the stub carries systemd's EDID panel-ID code: $edid"; else bad "the stub shows no EDID panel-ID code"; fi
echo "--- systemd-stub with the panel EDID readable (panel $panel):"
python3 "$build/edge/hwids.py" match "$work/sections/.hwids" --panel "$panel"
echo "--- systemd-stub without a panel EDID:"
python3 "$build/edge/hwids.py" match "$work/sections/.hwids"

step "3. Live kernel and initramfs"
kver=$(cat "$work/sections/.uname")
echo "kernel release: $kver"
echo "live root: $(local_index "$live" | awk -F'\t' '$1 ~ /^(linux-omarchy|linux-omarchy-dtbs|systemd|systemd-stub-omarchy|systemd-ukify)$/ { printf "%s %s, ", $1, $2 }')"
lsinitcpio "$work/sections/.initrd" >"$out/initrd-uki.txt" || bad "lsinitcpio could not read the UKI's .initrd"
lsinitcpio "$mnt/iso/arch/boot/aarch64/initramfs-linux-omarchy.img" >"$out/initrd-direct.txt" || bad "lsinitcpio could not read the direct-boot initramfs"
kmods=$live/usr/lib/modules/$kver
echo "UKI .initrd: $(wc -l <"$out/initrd-uki.txt") entries; direct-boot initramfs: $(wc -l <"$out/initrd-direct.txt") entries"
printf '%-30s %-16s %-16s %s\n' module "UKI .initrd" "direct initrd" kernel
for m in "${modules[@]}"; do
  re="${m//[-_]/[-_]}"
  in_kernel=$(find "$kmods" -regextype posix-extended -regex ".*/$re\.ko(\.(zst|xz|gz))?" -printf '%P\n' -quit)
  if grep -qE "/$re\.ko$" "$kmods/modules.builtin" 2>/dev/null; then kernel=built-in
  elif [[ -n $in_kernel ]]; then kernel="module ($in_kernel)"
  else kernel=ABSENT
  fi
  u=$(grep -qE "/$re\.ko(\.(zst|xz|gz))?$" "$out/initrd-uki.txt" && echo yes || echo no)
  d=$(grep -qE "/$re\.ko(\.(zst|xz|gz))?$" "$out/initrd-direct.txt" && echo yes || echo no)
  printf '%-30s %-16s %-16s %s\n' "$m" "$u" "$d" "$kernel"
done
echo "every surface_aggregator* module in the kernel:"
find "$kmods" -name 'surface_aggregator*' -printf '  %P\n'
# surface-pro-11.sh tells the LCD model by /sys/devices/soc0/soc_id.
socinfo=$(grep -E '/socinfo\.ko$' "$kmods/modules.builtin" 2>/dev/null)
echo "qcom socinfo (soc0/soc_id): ${socinfo:+built-in ($socinfo)}${socinfo:-module $(find "$kmods" -name 'socinfo.ko*' -printf '%P')}"

step "4. Package versions: offline mirror db, files shipped on the ISO, root image, live root"
mirror=$live/var/cache/omarchy/mirror/offline
db_index "$mirror/offline.db.tar.gz" >"$out/offline-db.tsv"
local_index "$root" >"$out/root-image-packages.tsv"
local_index "$live" >"$out/live-root-packages.tsv"
echo "offline.db: $(wc -l <"$out/offline-db.tsv") packages; shipped files: $(find "$mirror" -maxdepth 1 -name '*.pkg.tar.*' ! -name '*.sig' | wc -l); root image: $(wc -l <"$out/root-image-packages.tsv") packages"
printf '%-40s %-34s %-8s %-34s %s\n' package "offline.db" shipped "root image" "live root"
for p in "${packages[@]}"; do
  read -r dbv file < <(awk -F'\t' -v p="$p" '$1 == p { print $2, $3 }' "$out/offline-db.tsv")
  shipped=no; [[ -n ${file:-} && -f $mirror/$file ]] && shipped=yes
  imv=$(awk -F'\t' -v p="$p" '$1 == p { print $2 }' "$out/root-image-packages.tsv")
  lv=$(awk -F'\t' -v p="$p" '$1 == p { print $2 }' "$out/live-root-packages.tsv")
  printf '%-40s %-34s %-8s %-34s %s\n' "$p" "${dbv:--}" "$shipped" "${imv:--}" "${lv:--}"
  unset dbv file
done
if [[ -n ${CACHE_MIRROR:-} ]]; then
  echo "build cache $CACHE_MIRROR against the ISO's offline.db:"
  for p in omarchy-dev omarchy-settings-dev; do
    read -r version file < <(awk -F'\t' -v p="$p" '$1 == p { print $2, $3 }' "$out/offline-db.tsv")
    want=$(bsdtar -xOf "$mirror/offline.db.tar.gz" --include="$p-$version/desc" | awk '/^%SHA256SUM%$/ { getline s; print s }')
    have=$(sha256sum "$CACHE_MIRROR/$file" 2>/dev/null | cut -d' ' -f1)
    if [[ -n $want && $want == "$have" ]]; then ok "$file in the build cache has the offline.db SHA256 $want"; else bad "$file: cache ${have:-missing}, offline.db ${want:-missing}"; fi
  done
fi

step "5. The installer's Surface Pro 11 setup"
if [[ -f $root/$spec ]]; then
  cp "$root/$spec" "$out/surface-pro-11.sh"
  echo "/$spec: owned by $(owner "$root" "$spec"), sha256 $(sha256sum "$root/$spec" | cut -d' ' -f1)"
  grep -nE '615|x1p64100|denali|soc_id|panel' "$root/$spec"
  if grep -qE '== "615"' "$root/$spec" && grep -q 'surface_pro11_tree=x1p64100-microsoft-denali$' "$root/$spec"; then
    ok "surface-pro-11.sh has the soc_id 615 branch that pins x1p64100-microsoft-denali.dtb"
  else
    bad "surface-pro-11.sh lacks the soc_id 615 / x1p64100-microsoft-denali branch"
  fi
else
  bad "/$spec is not in the root image"
fi
dtb=boot/dtbs/linux-omarchy/qcom/x1p64100-microsoft-denali.dtb
if [[ -f $root/$dtb ]]; then ok "/$dtb is in the root image (owned by $(owner "$root" "$dtb"))"; else bad "/$dtb is not in the root image"; fi
echo "the pre.d hook that refreshes the device tree list before every UKI build:"
grep -nE 'leaves any other|Nothing of ours to refresh' "$root/usr/bin/omarchy-update-qualcomm-device-trees" | sed 's/^/  /'
grep -nE 'qualcomm/dtb-uki.sh|microsoft/surface-pro-11.sh' "$root/usr/share/omarchy/install/hardware/all.sh" | sed 's/^/  all.sh:/'
echo "callers of surface-pro-11.sh in the runtime:"
grep -rn 'surface-pro-11' "$root/usr/share/omarchy/install" --include='*.sh' --include='*.packages' | grep -v "^$root/$spec:" | sed "s|^$root/||"

step "6. The Surface Pro 11 packages, firmware and Wi-Fi board data"
for p in microsoft-surface-pro-11-support microsoft-surface-pro-11-sensors microsoft-surface-pro-11-firmware microsoft-surface-snapdragon-addresses iptsd; do
  file=$(awk -F'\t' -v p="$p" '$1 == p { print $3 }' "$out/offline-db.tsv")
  dest=$work/pkgs/$p
  rm -rf "$dest" && mkdir -p "$dest"
  if [[ -n $file && -f $mirror/$file ]]; then
    bsdtar -xf "$mirror/$file" -C "$dest"
    bsdtar -tf "$mirror/$file" | grep -v '/$' | grep -v '^\.' >"$out/files-$p.txt"
    echo "$p ($file): $(wc -l <"$out/files-$p.txt") files"
    oled=$(grep -rlI 'denali-oled' "$dest" | grep -v '/usr/share/doc/' | sed "s|^$dest/||")
    docs=$(grep -rlI 'denali-oled' "$dest/usr/share/doc" 2>/dev/null | sed "s|^$dest/||")
    if [[ -n $oled ]]; then bad "$p is still gated on microsoft,denali-oled in: $oled"; else ok "$p has no microsoft,denali-oled gate${docs:+ (named only in $docs)}"; fi
  else
    bad "$p is not shipped in the offline mirror"
  fi
done
echo "device tree gates in the support and sensors packages (outside their docs):"
grep -rnI 'denali' "$work/pkgs/microsoft-surface-pro-11-support" "$work/pkgs/microsoft-surface-pro-11-sensors" |
  grep -v '/usr/share/doc/' | sed "s|^$work/pkgs/|  |"
# The support package ships Qualcomm's reference-design record (subsystem-device
# 3378, board-id 255) as board.bin: 88872 bytes, this SHA256.
board=$work/pkgs/microsoft-surface-pro-11-support/usr/lib/firmware/ath12k/WCN7850/hw2.0/board.bin.xz
if [[ -f $board ]] && [[ $(xz -dc "$board" | sha256sum | cut -d' ' -f1) == 0ef5f6f3cb124f33c6de52371819ccd7c13763ceb86d476a178fd56e4cdc26a3 ]]; then
  ok "the support package's ath12k board.bin is Qualcomm's 3378/255 reference record ($(xz -dc "$board" | wc -c) bytes)"
else
  bad "the support package has no board.bin, or it is not Qualcomm's 3378/255 reference record"
fi
# ath12k reads board.bin only when board-2.bin has no exact match for the card.
board2=$(compgen -G "$root/usr/lib/firmware/ath12k/WCN7850/hw2.0/board-2.bin*" | head -1)
exact='bus=pci,vendor=17cb,device=1107,subsystem-vendor=17cb,subsystem-device=1107,qmi-chip-id=2,qmi-board-id=255'
if [[ -n $board2 ]]; then
  case $board2 in *.zst) cat2=(zstd -dcq) ;; *.xz) cat2=(xz -dc) ;; *) cat2=(cat) ;; esac
  # The name ends where its element does: no further digit, and no ",variant=".
  # No grep -q: under pipefail, its early exit would fail the pipe with SIGPIPE.
  if "${cat2[@]}" "$board2" | grep -aE "$exact([^0-9,]|\$)" >/dev/null; then
    echo "NOTE: ${board2#"$root/"} ($(owner "$root" "${board2#"$root/"}")) has an exact record for this card: $exact"
  else
    echo "NOTE: ${board2#"$root/"} ($(owner "$root" "${board2#"$root/"}")) has no exact record for $exact"
  fi
fi
echo "packages providing the Surface Pro 11's firmware folders (qualcomm/oem-firmware.sh installs by these names):"
bsdtar -xOf "$mirror/offline.db.tar.gz" --include='*/desc' |
  awk '/^%NAME%$/ { getline n } /^%PROVIDES%$/ { while ((getline p) > 0 && p != "") if (p ~ /^qcom-firmware-x1e80100-microsoft(-denali)?$/) print "  " n ": " p }'
echo "how the sensors package gets its configuration:"
grep -rnE 'DriverStore|Windows|FileRepository|\.ini|-extract' "$work/pkgs/microsoft-surface-pro-11-sensors" 2>/dev/null | grep -v Binary | head -20 | sed "s|^$work/pkgs/||"
if command -v dtc >/dev/null && ((${#lcd[@]} == 1)); then
  echo "firmware the LCD tree names (firmware-name), and where it comes from:"
  dtc -q -I dtb -O dts "$work/sections/${lcd[0]}" 2>/dev/null |
    sed -n 's/.*firmware-name = \(.*\);/\1/p' | tr -d '"' | tr ',' '\n' | sed 's/^ *//' | sort -u >"$out/lcd-firmware-names.txt"
  medium=$mnt/iso/arch/aarch64/qcom-firmware
  while read -r fw; do
    from=()
    grep -qxE "usr/lib/firmware/$fw(\.(xz|zst))?" "$out/files-microsoft-surface-pro-11-firmware.txt" 2>/dev/null && from+=(microsoft-surface-pro-11-firmware)
    compgen -G "$root/usr/lib/firmware/$fw*" >/dev/null && from+=("root image ($(owner "$root" "$(cd "$root" && compgen -G "usr/lib/firmware/$fw*" | head -1)"))")
    [[ -f $medium/SHA256SUMS ]] && grep -qF "$fw" "$medium/SHA256SUMS" && from+=("medium qcom-firmware/ (live ADSP)")
    printf '  %-60s %s\n' "$fw" "${from[*]:-NOWHERE}"
  done <"$out/lcd-firmware-names.txt"
fi
echo "the Snapdragon UKI setup the installed system runs (device tree choice):"
grep -nE 'denali|DeviceTree|dtbauto|hwids' "$root/usr/share/omarchy/install/hardware/qualcomm/"*.sh 2>/dev/null | sed "s|^$root/||" | head -30

echo
if ((fails == 0)); then echo "verify: every check passed"; else echo "verify: $fails check(s) failed"; fi
exit $((fails > 0))
