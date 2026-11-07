#!/usr/bin/env bash
# Pre-fetch the Surface Pro 11 packages the live USB cannot download itself.
#
# The live system has no Wi-Fi (no board data, DSP off), so finish-install.sh
# installs these from the USB. They are Omarchy's own signed packages, taken
# from its edge repository, plus whatever dependencies the target root image
# does not have yet, from the stable ARM mirror the installed system will use.
# pacman resolves the set inside the official target root image (copy-on-write
# overlay), so it always matches the release being remastered and nothing
# already in the image is fetched twice. Signatures come along; pacman -U on the
# target verifies them with the keyrings the installer sets up.
#
# Runs in the privileged build container (needs loop and overlay mounts):
#   /in   official ISO (read-only)      /out  staged payload's pkgs/ directory
#   /work scratch volume
set -euo pipefail

version=${OMARCHY_VERSION:-4.5.0}
iso=/in/omarchy-$version-aarch64.iso
out=/out
packages=(
  microsoft-surface-pro-11-firmware
  microsoft-surface-pro-11-support
  microsoft-surface-pro-11-sensors
  microsoft-surface-snapdragon-addresses
  iptsd
  pipewire-libcamera
)
work=/work/fetch
die() { echo "fetch-packages: $*" >&2; exit 1; }

mkdir -p "$work" "$out"
cd "$work"
if [[ ! -f root.img ]]; then
  # Reuse the image the chroot test unpacked, when it is there.
  if [[ -f /work/chroot-test/root.img ]]; then
    ln -s /work/chroot-test/root.img root.img
  else
    xorriso -osirrox on -indev "$iso" -extract /arch/aarch64/omarchy-root.img.zst root.img.zst >/dev/null 2>&1
    zstd -dq --rm root.img.zst -o root.img
  fi
fi

rm -rf upper merged && mkdir -p lower upper merged
mount -o loop,ro root.img lower
mount -t tmpfs tmpfs upper && mkdir -p upper/u upper/w
mount -t overlay overlay -o lowerdir=lower/omarchy-root,upperdir=upper/u,workdir=upper/w merged
for d in proc sys dev; do mount --rbind /$d merged/$d; done
mkdir -p merged/tmp/pkgs && mount --bind "$out" merged/tmp/pkgs
cleanup() { cd /; umount -R "$work/merged" 2>/dev/null || true; umount "$work/upper" "$work/lower" 2>/dev/null || true; }
trap cleanup EXIT
R=merged
cp -L /etc/resolv.conf "$R/etc/resolv.conf"

# Omarchy's edge repository in place of stable, and Arch Linux ARM through the
# stable mirror the installed system uses. pacman names a repository's database
# after its section and Omarchy serves only omarchy.db, so edge cannot sit
# beside stable as a second section; here that does not matter, since every
# Omarchy package the image carries is already installed and only the
# requested packages and their Arch Linux ARM dependencies get fetched.
cat >"$R/etc/pacman.conf" <<'CONF'
[options]
HoldPkg = pacman glibc
Architecture = auto
SigLevel = Required DatabaseOptional
LocalFileSigLevel = Optional
ParallelDownloads = 5

[omarchy]
Server = https://pkgs.omarchy.org/edge/$arch
[core]
Server = https://arm-stable-mirror.omarchy.org/$arch/$repo
[extra]
Server = https://arm-stable-mirror.omarchy.org/$arch/$repo
[alarm]
Server = https://arm-stable-mirror.omarchy.org/$arch/$repo
CONF

chroot "$R" pacman-key --init >/dev/null 2>&1
chroot "$R" pacman-key --populate archlinuxarm omarchy >/dev/null 2>&1 || die "cannot populate the keyrings"

echo "==> Resolving ${packages[*]} against the $version target image"
chroot "$R" pacman -Syw --noconfirm --cachedir /tmp/pkgs "${packages[@]}"

# Every fetched package must carry its signature. Nothing the image already
# has may be fetched again from edge: that would be a newer Omarchy package
# replacing a stable one on the target.
for pkg in "$out"/*.pkg.tar.*; do
  pkg=$(basename "$pkg")
  [[ $pkg == *.sig ]] && continue
  [[ -s $out/$pkg.sig ]] || die "$pkg has no signature"
  # The image's own pacman reads the package (every compression it uses).
  name=$(chroot "$R" pacman -Qpq "/tmp/pkgs/$pkg" 2>/dev/null) || die "$pkg is not a package pacman can read"
  if compgen -G "$R/var/lib/pacman/local/$name-[0-9]*" >/dev/null; then
    die "$name is already in the image; the fetch should not replace stable packages"
  fi
done
cd "$out"
rm -f *.part
echo "==> $(ls *.pkg.tar.* | grep -vc '\.sig$') packages, $(du -sh . | cut -f1):"
ls *.pkg.tar.* | grep -v '\.sig$' | sed 's/^/  /'
