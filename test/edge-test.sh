#!/usr/bin/env bash
# Test a remastered ISO against the Omarchy edge ISO it was built from, in a
# privileged Arch Linux ARM container (build/edge/Dockerfile). Run through
# test/edge-test.ps1:
#   edge-test.sh BASE_ISO OUT_ISO
#   /repo   this repository (read-only)      /work   scratch (a Docker volume)
# Nothing is written to either ISO or to the target root image (an overlay).
#
# What this repository is responsible for:
#  1. The result boots like the base: volume UUID and dates, El Torito and GPT,
#     grub.cfg, every file of the base unchanged (with the fallback, all but
#     the live UKI), and the medium's own checksums pass.
#  2. /sp11-lcd: every file of payload/ (setup.sh, README.md, camera/), and
#     windows/ complete against its own SHA256SUMS.
#  3. The live UKI: Omarchy's own, with build/edge/verify-edge-iso.sh passing
#     on the result; or with the fallback, the LCD-only rebuild.
#  4. setup.sh, run twice from the mounted result inside the edge target root
#     image, with the root image's own LCD device tree and the X1P-64-100's
#     socinfo ID.
#  5. Facts the docs state: the archive's firmware against Omarchy's firmware
#     package, and the CHIDs of contrib/ against Omarchy's and against
#     device-facts.json.
set -uo pipefail

base=$(readlink -f "${1:?usage: edge-test.sh BASE_ISO OUT_ISO}")
out=$(readlink -f "${2:?usage: edge-test.sh BASE_ISO OUT_ISO}")
repo=/repo
W=/work/test
mnt=$W/mnt
uki_path=arch/boot/aarch64/omarchy-live.efi
compat=microsoft,denali-lcd
fails=0
ok() { echo "PASS: $*"; }
bad() { echo "FAIL: $*"; fails=$((fails + 1)); }
step() { echo; echo "==> $*"; }

mkdir -p "$mnt"/{base,out,live,lower,root}
cleanup() {
  umount -R "$mnt/root" 2>/dev/null
  umount "$mnt/lower" "$mnt/live" "$mnt/out" "$mnt/base" 2>/dev/null
  rm -rf "$W/upper"
}
trap cleanup EXIT
mount -o loop,ro "$base" "$mnt/base" || { echo "cannot mount $base"; exit 2; }
mount -o loop,ro "$out" "$mnt/out" || { echo "cannot mount $out"; exit 2; }
mount -o loop,ro -t squashfs "$mnt/out/arch/aarch64/airootfs.sfs" "$mnt/live" || { echo "cannot mount airootfs.sfs"; exit 2; }
echo "base: $base ($(stat -c %s "$base") bytes)"
echo "out:  $out ($(stat -c %s "$out") bytes)"
if cmp -s "$mnt/base/$uki_path" "$mnt/out/$uki_path"; then fallback=0; else fallback=1; fi
echo "mode: $( ((fallback)) && echo 'fallback (rebuilt live UKI)' || echo "default (Omarchy's live UKI)")"

step "1. Boot layout and base files"
pvd() { xorriso -indev "$1" -pvd_info 2>/dev/null | sed -n "s/^$2 *: //p"; }
for field in "Volume Id" "Creation Time" "Modif. Time"; do
  [[ $(pvd "$base" "$field") == "$(pvd "$out" "$field")" ]] && ok "$field kept: $(pvd "$out" "$field")" || bad "$field changed"
done
uuid=$(blkid -p -o value -s UUID "$out")
[[ $uuid == "$(blkid -p -o value -s UUID "$base")" ]] && ok "volume UUID kept: $uuid" || bad "volume UUID changed"
report() { xorriso -indev "$1" -report_el_torito plain -report_system_area plain 2>/dev/null | grep -vE '^(Drive|Media|Boot record|Volume id|xorriso)'; }
normalize() { sed -E '/GUID/!s/[0-9]+/N/g'; }
diff <(report "$base" | normalize) <(report "$out" | normalize) >/dev/null &&
  ok "El Torito and GPT records match the base (kinds, order, GUIDs; addresses may move)" || bad "boot records differ"
report "$out" | grep -E 'GPT disk GUID|El Torito boot img'
# GRUB itself is in the appended EFI partition (GPT partition 2, also El
# Torito's UEFI image), outside the file tree diff -rq sees below.
efi() {
  local start size
  read -r start size < <(xorriso -indev "$1" -report_system_area plain 2>/dev/null | awk '/^GPT start and size :   2 / { print $7, $8 }')
  [[ -n $start ]] && dd if="$1" bs=512 skip="$start" count="$size" status=none | sha256sum | cut -d' ' -f1
}
efi_base=$(efi "$base")
[[ -n $efi_base && $efi_base == "$(efi "$out")" ]] && ok "the EFI boot partition (GRUB) is byte-identical to the base's: $efi_base" || bad "the EFI boot partition differs"
cmp -s "$mnt/base/boot/grub/grub.cfg" "$mnt/out/boot/grub/grub.cfg" && ok "grub.cfg unchanged" || bad "grub.cfg changed"
chains=$(grep -cE "^[[:space:]]*chainloader /$uki_path .*archisosearchuuid=$uuid " "$mnt/out/boot/grub/grub.cfg")
others=$(grep -E '^[[:space:]]*chainloader /arch/' "$mnt/out/boot/grub/grub.cfg" | grep -cv "chainloader /$uki_path ")
((chains == 2 && others == 0)) && ok "both device tree entries chainload /$uki_path on UUID $uuid" || bad "$chains entries chainload the UKI, $others other /arch files"
want="Only in $mnt/out: sp11-lcd"
((fallback)) && want+=$'\n'"Files $mnt/base/$uki_path and $mnt/out/$uki_path differ"
# The El Torito catalog holds the boot image's block address, which moves;
# the boot record comparison above covers what it says.
cat_path=$(xorriso -indev "$out" -report_el_torito plain 2>/dev/null | sed -n 's/^El Torito cat path : //p')
have=$(diff -rq "$mnt/base" "$mnt/out" 2>&1 | grep -vxF "Files $mnt/base$cat_path and $mnt/out$cat_path differ" | sort)
[[ $have == "$(sort <<<"$want")" ]] && ok "every base file is on the result unchanged; it adds /sp11-lcd$( ((fallback)) && echo ' and replaces the live UKI')" ||
  { bad "the result differs from the base beyond the intended change:"; echo "$have" | head -20; }
(cd "$mnt/out/arch/aarch64" && sha256sum --quiet -c omarchy-root.img.zst.sha256) && ok "omarchy-root.img.zst.sha256 passes on the result" || bad "root image checksum"
(cd "$mnt/out/arch/aarch64" && sha512sum --quiet -c airootfs.sha512) && ok "airootfs.sha512 passes on the result" || bad "airootfs checksum"
(cd "$mnt/out/arch/aarch64/qcom-firmware" && sha256sum --quiet -c SHA256SUMS) && ok "qcom-firmware/SHA256SUMS passes on the result" || bad "medium firmware checksums"

step "2. /sp11-lcd"
while IFS= read -r f; do
  cmp -s "$repo/payload/sp11-lcd/$f" "$mnt/out/sp11-lcd/$f" && ok "/sp11-lcd/$f is payload/sp11-lcd/$f" || bad "/sp11-lcd/$f differs from the repository"
done < <(cd "$repo/payload/sp11-lcd" && find . -type f -printf '%P\n' | sort)
for f in camera/setup-camera.sh touchscreen/setup-touchscreen.sh touchscreen/surface-touchscreen ir-camera/setup-ir-camera.sh; do
  bash -n "$mnt/out/sp11-lcd/$f" && ok "$f parses" || bad "$f does not parse"
done
python3 -c 'import ast, sys; ast.parse(open(sys.argv[1]).read())' "$mnt/out/sp11-lcd/ir-camera/surface-ir-emitter" &&
  ok "ir-camera/surface-ir-emitter parses" || bad "ir-camera/surface-ir-emitter does not parse"
win=$mnt/out/sp11-lcd/windows
(cd "$win" && sha256sum --quiet -c SHA256SUMS) && ok "windows/: $(wc -l <"$win/SHA256SUMS") files match SHA256SUMS" || bad "windows/ does not match SHA256SUMS"
[[ $(find "$win" -type f ! -name SHA256SUMS | wc -l) == $(wc -l <"$win/SHA256SUMS") ]] && ok "SHA256SUMS lists every file under windows/" || bad "files under windows/ that SHA256SUMS does not list"
echo "windows/: $(du -sh "$win" | cut -f1), $(find "$win/FileRepository" -mindepth 1 -maxdepth 1 -type d | wc -l) driver packages"
facts=$win/device-facts.json
tuning=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["audio"]["dolby_tuning_xml"] or "")' "$facts")
[[ -n $tuning && -s $win/$tuning ]] && ok "the Dolby speaker tuning dolby2pipewire.py reads is archived: $tuning" || bad "no Dolby tuning XML in the archive"
compgen -G "$win/FileRepository/surfacepro_snscfgcrd8380.inf_arm64_*/json.lst" >/dev/null && ok "the light sensor configuration is archived" || bad "no sensor configuration in the archive"

step "3. Live UKI"
rm -rf "$W/s-base" "$W/s-out"
python3 "$repo/build/uki-dtb.py" split "$mnt/base/$uki_path" "$W/s-base" >"$W/dtbs-base.txt"
if ((fallback)); then
  python3 "$repo/build/uki-dtb.py" check "$mnt/out/$uki_path" "$compat" && ok "uki-dtb.py check: boots only $compat" || bad "uki-dtb.py check"
  python3 "$repo/build/uki-dtb.py" split "$mnt/out/$uki_path" "$W/s-out" >/dev/null
  for s in .linux .initrd .osrel .uname; do
    cmp -s "$W/s-base/$s" "$W/s-out/$s" && ok "$s byte-identical to Omarchy's UKI" || bad "$s differs from Omarchy's UKI"
  done
  lcd=$(awk -F'\t' -v c="$compat" '$2 == c { print $1 }' "$W/dtbs-base.txt")
  cmp -s "$W/s-base/$lcd" "$W/s-out/.dtb" && ok ".dtb is Omarchy's own $compat tree ($lcd)" || bad ".dtb is not Omarchy's $compat tree"
  [[ ! -e $W/s-out/.cmdline && ! -e $W/s-out/.dtbauto.0 ]] && ok "no .cmdline (GRUB's command line applies) and no .dtbauto" || bad "unexpected .cmdline or .dtbauto"
  size=$(stat -c %s "$mnt/out/$uki_path")
  ((size <= 256 * 1024 * 1024)) && ok "$size bytes, within omarchy-iso's 256 MiB limit" || bad "$size bytes, over 256 MiB"
  grep -a 'systemd-stub.arch' "$W/s-out/.sbat" | tr -d '\0'
else
  ok "the live UKI is Omarchy's own, byte for byte"
  BUILD_DIR=$repo/build bash "$repo/build/edge/verify-edge-iso.sh" "$out" "$W/verify" >"$W/verify.log" 2>&1
  status=$?
  grep -E '^(PASS|FAIL|NOTE)' "$W/verify.log" | sed 's/^/  verify-edge-iso.sh: /'
  ((status == 0)) && ok "build/edge/verify-edge-iso.sh passes on the result ($W/verify/report.txt)" || bad "verify-edge-iso.sh (see $W/verify/report.txt)"
fi

step "4. setup.sh in the edge target root image"
# Shared with verify-edge-iso.sh, and reused only if it came from this ISO.
root_img=$W/verify/work/root.img
zst_sum=$(awk '$2 == "omarchy-root.img.zst" { print $1 }' "$mnt/out/arch/aarch64/omarchy-root.img.zst.sha256")
if [[ ! -s $root_img || $(cat "$root_img.sha256" 2>/dev/null) != "$zst_sum" ]]; then
  mkdir -p "$(dirname "$root_img")" && rm -f "$root_img" "$root_img.sha256"
  zstd -dq "$mnt/out/arch/aarch64/omarchy-root.img.zst" -o "$root_img.part" && mv "$root_img.part" "$root_img" &&
    echo "$zst_sum" >"$root_img.sha256"
fi
echo "root image: ${root_img#"$W/"} from omarchy-root.img.zst $zst_sum"
mount -o loop,ro "$root_img" "$mnt/lower"
# The overlay's writes (two copies of the archive at a time) go to the scratch
# volume rather than memory.
rm -rf "$W/upper" && mkdir -p "$W/upper/u" "$W/upper/w"
mount -t overlay overlay -o "lowerdir=$mnt/lower/omarchy-root,upperdir=$W/upper/u,workdir=$W/upper/w" "$mnt/root"
R=$mnt/root
for d in proc sys dev; do mount --rbind "/$d" "$R/$d"; done
mount -t tmpfs tmpfs "$R/tmp"
mount -t tmpfs tmpfs "$R/run"
mkdir -p "$R/mnt" && mount --bind "$mnt/out" "$R/mnt"
# What the installer's surface-pro-11.sh does for the sensors: the package
# from the ISO's offline mirror, and its service enabled.
mirror=$mnt/live/var/cache/omarchy/mirror/offline
pkg=$(find "$mirror" -name 'microsoft-surface-pro-11-sensors-*.pkg.tar.zst' | head -1)
cp "$pkg" "$R/tmp/"
chroot "$R" pacman -U --noconfirm --nodeps --nodeps "/tmp/$(basename "$pkg")" >"$W/pacman.log" 2>&1 &&
  ok "installed $(basename "$pkg") from the ISO's offline mirror" || bad "pacman -U (see $W/pacman.log)"
chroot "$R" systemctl enable surface-pro-11-sensors.service >/dev/null 2>&1
dtb=$R/boot/dtbs/linux-omarchy/qcom/x1p64100-microsoft-denali.dtb
python3 "$repo/test/dtb2fs.py" "$dtb" "$R/tmp/dt"
mkdir -p "$R/tmp/soc0"
echo 615 >"$R/tmp/soc0/soc_id"
tr -d '\r\n' <"$(compgen -G "$win/FileRepository/surfacepro_snscfgcrd8380.inf_arm64_*/revision" | head -1)" >"$R/tmp/soc0/revision"
echo "device tree: $(tr '\0' ' ' <"$R/tmp/dt/compatible")(${dtb#"$R"})"
run_setup() {
  chroot "$R" env SP11_SENSORS_COMPATIBLE="$1" SP11_SENSORS_SOC=/tmp/soc0 bash /mnt/sp11-lcd/setup.sh
}
run_setup /tmp/dt/compatible >"$W/setup1.log" 2>&1 && ok "setup.sh from the mounted ISO exits 0" || { bad "setup.sh (see $W/setup1.log)"; tail -5 "$W/setup1.log"; }
dest=$R/var/lib/sp11-lcd
[[ $(stat -c '%a %U' "$dest") == "700 root" ]] && ok "/var/lib/sp11-lcd is root-only (700)" || bad "/var/lib/sp11-lcd is $(stat -c '%a %U' "$dest")"
[[ -z $(find "$dest" -perm /077 -print -quit) ]] && ok "nothing under it is readable by others" || bad "group/other permissions under /var/lib/sp11-lcd"
(cd "$dest/windows" && sha256sum --quiet -c SHA256SUMS) && ok "the copy matches SHA256SUMS ($(du -sh "$dest/windows" | cut -f1))" || bad "the copy does not match SHA256SUMS"
sroot=$R/var/lib/surface-pro-11-sensors/root
[[ -s $sroot/sensors/config/json.lst && -s $sroot/sensors/sns_reg.conf ]] && ok "sensor configuration extracted into /var/lib/surface-pro-11-sensors/root" || bad "no sensor configuration"
[[ $(tr -cd '\r' <"$sroot/sensors/sns_reg.conf" | wc -c) == 0 ]] && ok "sns_reg.conf without carriage returns" || bad "sns_reg.conf has CRs"
[[ $(cat "$sroot/socinfo/soc_id" 2>/dev/null) == 615 ]] && ok "socinfo/soc_id is 615" || bad "socinfo/soc_id"
grep -q '^source /var/lib/sp11-lcd/windows/FileRepository/surfacepro_snscfgcrd8380.inf_arm64_' "$sroot/manifest" &&
  ok "extracted from the copy on the system: $(head -1 "$sroot/manifest")" || bad "manifest source: $(head -1 "$sroot/manifest")"
grep -q 'differs from the qualified version' "$W/setup1.log" && echo "NOTE: $(grep 'differs from the qualified' "$W/setup1.log")" || ok "json.lst, the TCS3430 and colour sensor files have the hashes Omarchy qualified"
grep -q 'Not running under systemd' "$W/setup1.log" && ok "no service restart attempted outside a running systemd" || bad "setup.sh did not notice it runs without systemd"
chroot "$R" systemctl is-enabled surface-pro-11-sensors.service >/dev/null 2>&1 && ok "surface-pro-11-sensors.service still enabled (by the installer's step, not by setup.sh)" || bad "service not enabled"
cp "$sroot/manifest" "$W/manifest1"
run_setup /tmp/dt/compatible >"$W/setup2.log" 2>&1 && cmp -s "$W/manifest1" "$sroot/manifest" &&
  ok "a second run exits 0 and yields the same configuration" || bad "second run (see $W/setup2.log)"
other=$(find "$R/boot/dtbs/linux-omarchy/qcom" -name 'x1e80100-lenovo-yoga-slim7x.dtb' | head -1)
python3 "$repo/test/dtb2fs.py" "$other" "$R/tmp/dt-other"
if run_setup /tmp/dt-other/compatible >"$W/setup3.log" 2>&1; then bad "setup.sh ran on a Yoga Slim 7x tree"; else ok "setup.sh refuses a non-Surface tree: $(tail -1 "$W/setup3.log")"; fi

step "5. Facts the documentation states"
fwpkg=$(find "$mirror" -name 'microsoft-surface-pro-11-firmware-*.pkg.tar.zst' | head -1)
rm -rf "$W/fw" && mkdir -p "$W/fw" && bsdtar -xf "$fwpkg" -C "$W/fw"
echo "$(basename "$fwpkg") against this machine's driver store:"
same=0 total=0
while IFS= read -r f; do
  name=$(basename "${f%.xz}")
  case $name in adsp_dtb.mbn) win_name=adsp_dtbs.elf ;; cdsp_dtb.mbn) win_name=cdsp_dtbs.elf ;; *) win_name=$name ;; esac
  sum=$(xz -dc "$f" | sha256sum | cut -d' ' -f1)
  match=$(find "$win/FileRepository" -name "$win_name" -type f | while read -r c; do [[ $(sha256sum "$c" | cut -d' ' -f1) == "$sum" ]] && echo "${c#"$win/FileRepository/"}"; done | head -1)
  total=$((total + 1))
  if [[ -n $match ]]; then same=$((same + 1)); echo "  identical  ${f#"$W/fw/usr/lib/firmware/"}  = $match"
  else echo "  DIFFERENT  ${f#"$W/fw/usr/lib/firmware/"}  (sha256 $sum; driver store: $(find "$win/FileRepository" -name "$win_name" | sed "s|$win/FileRepository/||" | tr '\n' ' '))"
  fi
done < <(find "$W/fw/usr/lib/firmware" -name '*.xz' | sort)
((same == total)) && ok "all $total firmware files of the package are byte-identical to this machine's driver store copies" ||
  echo "NOTE: $same of $total firmware files are byte-identical to this machine's driver store copies"
shipped=$mnt/live/usr/lib/systemd/boot/hwids/aa64/linux-omarchy/x1p64100-microsoft-denali.json
cmp -s "$repo/contrib/systemd-x1p64100-microsoft-denali.json" "$shipped" &&
  ok "contrib/systemd-x1p64100-microsoft-denali.json is byte-identical to the file linux-omarchy-dtbs ships" || bad "contrib JSON differs from Omarchy's"
args=$(python3 -c '
import json, shlex, sys
d = json.load(open(sys.argv[1])); s = d["smbios"]
print(" ".join(shlex.quote(x) for x in ["--manufacturer", s["manufacturer"], "--family", s["family"], "--product-name", s["product_name"],
  "--product-sku", s["product_sku"], "--bb-manufacturer", s["baseboard_manufacturer"], "--bb-product", s["baseboard_product"], "--panel", d["panel"]["edid_panel_id"]]))' "$facts")
eval "set -- $args"
python3 "$repo/build/edge/hwids.py" match "$W/s-base/.hwids" "$@" >"$W/chid-panel.txt"
python3 "$repo/build/edge/hwids.py" match "$W/s-base/.hwids" "${@:1:12}" >"$W/chid-nopanel.txt"
for g in $(python3 -c 'import json,sys; print(" ".join(json.load(open(sys.argv[1]))["hwids"]))' "$repo/contrib/systemd-x1p64100-microsoft-denali.json"); do
  grep -q "$g" "$W/chid-panel.txt" || bad "device-facts.json does not yield $g"
done
grep -q "picks $compat via CHID EXTRA+2" "$W/chid-panel.txt" && ok "from device-facts.json with panel ${14}: $(tail -1 "$W/chid-panel.txt")" || bad "$(tail -1 "$W/chid-panel.txt")"
grep -q 'picks microsoft,denali-oled' "$W/chid-nopanel.txt" && ok "without the EDID: $(tail -1 "$W/chid-nopanel.txt") (the case -LcdOnlyUki covers)" || bad "$(tail -1 "$W/chid-nopanel.txt")"

echo
if ((fails == 0)); then echo "edge-test: every check passed"; else echo "edge-test: $fails check(s) failed"; fi
exit $((fails > 0))
