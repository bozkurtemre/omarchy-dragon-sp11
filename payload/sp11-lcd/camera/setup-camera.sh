#!/bin/bash
# Make the Surface Pro 11's front and back cameras usable by V4L2-only apps
# (Monologue, Omarchy's screen recording webcam overlay, ffmpeg/ffplay).
#
# Both cameras work through libcamera and PipeWire only (Chrome, Firefox and
# other PipeWire camera apps already see them). V4L2 has nothing but the raw
# CAMSS nodes, so V4L2 apps find no usable camera (omarchy-pkgs #3105). This
# relays each camera into a v4l2loopback device, on demand:
#   /dev/video40  Surface Front Camera   (imx681)
#   /dev/video41  Surface Back Camera    (ov13858)
#
# Run on the installed system, with network access, from the USB stick or a
# checkout of this repository (README.md next to it):
#   sudo bash /mnt/sp11-lcd/camera/setup-camera.sh
#
#  1. Installs v4l2loopback-dkms, gst-plugins-good and gst-plugin-pipewire
#     from Omarchy's repositories, and base-devel to build step 2.
#  2. Builds v4l2-relayd-sp11 (the AUR's v4l2-relayd plus this folder's
#     timestamp patch) as the invoking user and installs it.
#  3. Installs the module options, the relay user service, its two camera
#     configurations and a WirePlumber rule under /etc, and enables the
#     service for every user.
#  4. Loads the module and starts the relays for the invoking user's session.
# Safe to rerun.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
compatible=${SP11_CAMERA_COMPATIBLE:-/proc/device-tree/compatible}

die() { echo "sp11-camera: ERROR: $*" >&2; exit 1; }
step() { echo; echo "==> $*"; }

((EUID == 0)) || die "run as root: sudo bash $here/setup-camera.sh"
[[ ! -d /run/archiso ]] || die "this is the live USB session; run this on the installed system"
[[ -d /usr/share/omarchy ]] || die "no Omarchy installation here"
tr '\0' '\n' 2>/dev/null <"$compatible" | grep -qx 'microsoft,denali' ||
  die "the running device tree is not a Surface Pro 11's (no microsoft,denali in $compatible)"

# makepkg refuses root; build as the user who ran sudo (or pkexec).
user=${SUDO_USER:-}
[[ -z $user && -n ${PKEXEC_UID:-} ]] && user=$(id -nu "$PKEXEC_UID")
[[ -n $user && $user != root ]] || die "run through sudo from your own account, so the relay can be built as that user"

step "Packages from Omarchy's repositories"
pacman -S --needed --noconfirm base-devel v4l2loopback-dkms gst-plugins-good gst-plugin-pipewire

step "v4l2-relayd-sp11"
pkgsrc=$here/v4l2-relayd-sp11
want=$(source "$pkgsrc/PKGBUILD" && echo "$pkgname $pkgver-$pkgrel")
if [[ $(pacman -Q v4l2-relayd-sp11 2>/dev/null) == "$want" ]]; then
  echo "$want is installed"
else
  # The unpatched AUR package conflicts with it; pacman -U --noconfirm would
  # refuse to remove it on its own.
  if pacman -Q v4l2-relayd >/dev/null 2>&1; then pacman -Rdd --noconfirm v4l2-relayd; fi
  build=$(runuser -u "$user" -- mktemp -d)
  trap 'rm -rf "$build"' EXIT
  cp "$pkgsrc/PKGBUILD" "$pkgsrc/monotonic-timestamps.patch" "$build/"
  chown "$user:" "$build"/*
  runuser -u "$user" -- bash -c 'cd "$1" && makepkg --cleanbuild --noconfirm' _ "$build"
  pacman -U --noconfirm "$build"/v4l2-relayd-sp11-*.pkg.tar.*
  rm -rf "$build"
  trap - EXIT
fi

step "Configuration under /etc"
install -Dm644 "$here/v4l2loopback.conf" /etc/modprobe.d/surface-pro-11-cameras.conf
install -Dm644 /dev/stdin /etc/modules-load.d/surface-pro-11-cameras.conf <<<"v4l2loopback"
install -Dm644 "$here/front.conf" /etc/surface-pro-11-cameras/front.conf
install -Dm644 "$here/back.conf" /etc/surface-pro-11-cameras/back.conf
install -Dm644 "$here/surface-camera@.service" /etc/systemd/user/surface-camera@.service
install -Dm644 "$here/wireplumber-hide-loopback.conf" /etc/wireplumber/wireplumber.conf.d/surface-pro-11-cameras.conf
systemctl --global enable surface-camera@front.service surface-camera@back.service

if [[ ! -d /run/systemd/system ]]; then
  echo
  echo "sp11-camera: not running under systemd; the cameras appear after the next boot"
  exit 0
fi

step "v4l2loopback"
names() { cat /sys/devices/virtual/video4linux/video4[01]/name 2>/dev/null | paste -sd, -; }
if [[ -d /sys/module/v4l2loopback && $(names) != "Surface Front Camera,Surface Back Camera" ]] &&
  ! modprobe -r v4l2loopback; then
  echo
  echo "sp11-camera: v4l2loopback is loaded with other options and in use; reboot to get the Surface cameras"
  exit 0
fi
modprobe v4l2loopback
udevadm settle
[[ $(names) == "Surface Front Camera,Surface Back Camera" ]] || die "/dev/video40 and /dev/video41 are not the Surface cameras: $(names)"
echo "/dev/video40 Surface Front Camera, /dev/video41 Surface Back Camera"

step "Relays for $user"
if systemctl --user -M "$user@" show-environment >/dev/null 2>&1; then
  systemctl --user -M "$user@" daemon-reload
  # Applies the WirePlumber rule; audio drops for a moment.
  systemctl --user -M "$user@" restart wireplumber.service
  systemctl --user -M "$user@" restart surface-camera@front.service surface-camera@back.service
  systemctl --user -M "$user@" is-active surface-camera@front.service surface-camera@back.service
else
  echo "$user has no running session; the relays start at the next login"
fi

echo
echo "sp11-camera: done. Pick \"Surface Front Camera\" or \"Surface Back Camera\" in V4L2 apps."
echo "Check: ffmpeg -f v4l2 -i /dev/video40 -frames:v 90 -f null -"
