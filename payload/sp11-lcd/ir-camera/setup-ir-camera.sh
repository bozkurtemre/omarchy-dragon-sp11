#!/bin/bash
# Make the Surface Pro 11's IR (Windows Hello) camera a plain V4L2 device,
# /dev/video42 "Surface IR Camera" (GREY, 644x604), with the IR light on only
# while something streams it. Face unlock (omaFace, Howdy) can then use it.
#
# Needs ../camera/setup-camera.sh first: it installs v4l2loopback and
# v4l2-relayd-sp11, and its v4l2loopback options carry the third device.
#
# Run on the installed system, with network access:
#   sudo bash /mnt/sp11-lcd/ir-camera/setup-ir-camera.sh
#
#  1. Installs gst-plugin-libcamera (the relay reads the sensor through it).
#  2. Updates the v4l2loopback options and reloads the module if
#     /dev/video42 is not there yet (stopping the front/back relays a moment).
#  3. Installs surface-ir-emitter to /usr/local/lib/surface-pro-11-ir/ and
#     the surface-ir-camera and surface-ir-emitter system services, and
#     enables them.
# Safe to rerun.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
compatible=${SP11_IR_COMPATIBLE:-/proc/device-tree/compatible}

die() { echo "sp11-ir-camera: ERROR: $*" >&2; exit 1; }
step() { echo; echo "==> $*"; }

((EUID == 0)) || die "run as root: sudo bash $here/setup-ir-camera.sh"
[[ ! -d /run/archiso ]] || die "this is the live USB session; run this on the installed system"
tr '\0' '\n' 2>/dev/null <"$compatible" | grep -qx 'microsoft,denali' ||
  die "the running device tree is not a Surface Pro 11's (no microsoft,denali in $compatible)"
pacman -Q v4l2-relayd-sp11 >/dev/null 2>&1 && pacman -Q v4l2loopback-dkms >/dev/null 2>&1 ||
  die "run ../camera/setup-camera.sh first (v4l2-relayd-sp11 and v4l2loopback-dkms are missing)"
[[ -e /sys/class/leds/ir:flash/brightness ]] || die "no IR light (/sys/class/leds/ir:flash); this tree does not describe it"

user=${SUDO_USER:-}
[[ -z $user && -n ${PKEXEC_UID:-} ]] && user=$(id -nu "$PKEXEC_UID")

step "Packages from Omarchy's repositories"
pacman -S --needed --noconfirm gst-plugin-libcamera v4l-utils python

step "v4l2loopback: /dev/video42"
install -Dm644 "$here/../camera/v4l2loopback.conf" /etc/modprobe.d/surface-pro-11-cameras.conf
name() { cat /sys/devices/virtual/video4linux/video42/name 2>/dev/null; }
if [[ $(name) != "Surface IR Camera" && -d /run/systemd/system ]]; then
  systemctl stop surface-ir-camera.service 2>/dev/null || true
  session=0
  if [[ -n $user ]] && systemctl --user -M "$user@" show-environment >/dev/null 2>&1; then
    session=1
    systemctl --user -M "$user@" stop surface-camera@front.service surface-camera@back.service || true
  fi
  if [[ -d /sys/module/v4l2loopback ]] && ! modprobe -r v4l2loopback; then
    echo "v4l2loopback is in use; the IR camera appears after a reboot"
  else
    modprobe v4l2loopback
    udevadm settle
  fi
  ((session)) && systemctl --user -M "$user@" start surface-camera@front.service surface-camera@back.service
fi

step "Services"
install -Dm755 "$here/surface-ir-emitter" /usr/local/lib/surface-pro-11-ir/surface-ir-emitter
install -Dm644 "$here/surface-ir-camera.service" /etc/systemd/system/surface-ir-camera.service
install -Dm644 "$here/surface-ir-emitter.service" /etc/systemd/system/surface-ir-emitter.service
systemctl daemon-reload
systemctl enable surface-ir-camera.service surface-ir-emitter.service

if [[ ! -d /run/systemd/system ]] || [[ $(name) != "Surface IR Camera" ]]; then
  echo
  echo "sp11-ir-camera: installed; /dev/video42 appears after the next boot"
  exit 0
fi
systemctl restart surface-ir-camera.service surface-ir-emitter.service
sleep 2
systemctl is-active surface-ir-camera.service surface-ir-emitter.service

echo
echo "sp11-ir-camera: done. /dev/video42 is the IR camera (GREY 644x604)."
echo "Check: ffmpeg -f v4l2 -i /dev/video42 -frames:v 90 -f null -   (the IR light comes on while it runs)"
