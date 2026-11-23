#!/bin/bash
# Make the menu's "Disable Touchscreen" trigger turn finger touch off.
#
# Omarchy's trigger turns off the first Hyprland touch device. On the Surface
# Pro 11 that is the raw spi-045e:0c80-touchscreen, which carries nothing:
# iptsd reads the touch data and sends finger touch through
# iptsd-virtual-touchscreen-045e:0c80, so touch keeps working. This installs
# surface-touchscreen, which turns off every touch device and leaves the pen,
# and points the two menu entries at it.
#
# Run as your own user (no sudo), on the installed system:
#   bash /mnt/sp11-lcd/touchscreen/setup-touchscreen.sh
#
#  1. Installs ~/.local/bin/surface-touchscreen.
#  2. Copies trigger.hardware.touchscreen-on/off from Omarchy's own menu,
#     with only the action changed, into a marked block of
#     ~/.config/omarchy/extensions/omarchy-menu.jsonc (search lists an
#     override without its label by its id). The menu reloads by itself.
# Safe to rerun: the block is replaced, the rest of the file is kept, and a
# backup is written before any change.
set -euo pipefail

here=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
compatible=${SP11_TOUCH_COMPATIBLE:-/proc/device-tree/compatible}
default_menu=${SP11_TOUCH_DEFAULT_MENU:-/usr/share/omarchy/default/omarchy/omarchy-menu.jsonc}
menu=$HOME/.config/omarchy/extensions/omarchy-menu.jsonc
bin=$HOME/.local/bin/surface-touchscreen
begin='  // BEGIN sp11-lcd touchscreen (setup-touchscreen.sh; rerun it instead of editing)'
end='  // END sp11-lcd touchscreen'

die() { echo "sp11-touchscreen: ERROR: $*" >&2; exit 1; }
step() { echo; echo "==> $*"; }

((EUID != 0)) || die "run as your own user, without sudo: bash $here/setup-touchscreen.sh"
tr '\0' '\n' 2>/dev/null <"$compatible" | grep -qx 'microsoft,denali' ||
  die "the running device tree is not a Surface Pro 11's (no microsoft,denali in $compatible)"
[[ -f $default_menu ]] || die "no Omarchy menu at $default_menu"

step "Installing $bin"
install -Dm755 "$here/surface-touchscreen" "$bin"

step "Menu entries in $menu"
entry() {
  local line old new
  line=$(grep -F "\"trigger.hardware.touchscreen-$1\": {" "$default_menu") ||
    die "Omarchy's menu has no trigger.hardware.touchscreen-$1 entry"
  old='"action":"omarchy-device-touchscreen"'
  new='"action":"\"$HOME/.local/bin/surface-touchscreen\" '"$1"'"'
  [[ $line == *"$old"* ]] || die "trigger.hardware.touchscreen-$1 no longer runs omarchy-device-touchscreen; check whether Omarchy fixed this"
  printf '%s\n' "${line/"$old"/"$new"}"
}
block="$begin
$(entry on)
$(entry off)
$end"

existed=1
if [[ ! -f $menu ]]; then
  existed=0
  mkdir -p "$(dirname "$menu")"
  printf '{\n}\n' >"$menu"
fi
# An override of the same ids outside the block would fight with it.
if awk -v b="$begin" -v e="$end" '$0 == b { s = 1 } !s && /"trigger\.hardware\.touchscreen-(on|off)"/ { f = 1 } $0 == e { s = 0 } END { exit !f }' "$menu"; then
  die "$menu already overrides trigger.hardware.touchscreen-on/off; remove those lines and rerun"
fi

tmp=$(mktemp)
trap 'rm -f "$tmp"' EXIT
# Drop the old block, then insert the new one before the closing brace. JSONC
# here allows trailing commas, but the entry before the block needs one.
BEGIN_LINE=$begin END_LINE=$end BLOCK=$block awk '
  $0 == ENVIRON["BEGIN_LINE"] { skip = 1; next }
  skip { if ($0 == ENVIRON["END_LINE"]) skip = 0; next }
  { lines[++n] = $0 }
  END {
    for (c = n; c > 0 && lines[c] !~ /^[[:space:]]*}[[:space:]]*$/; c--) ;
    if (c == 0) exit 2
    for (p = c - 1; p > 0 && lines[p] ~ /^[[:space:]]*(\/\/.*)?$/; p--) ;
    if (p > 0 && lines[p] !~ /[,{][[:space:]]*$/) lines[p] = lines[p] ","
    for (i = 1; i < c; i++) print lines[i]
    print ENVIRON["BLOCK"]
    for (i = c; i <= n; i++) print lines[i]
  }' "$menu" >"$tmp" || die "$menu does not end with a closing brace"

if cmp -s "$tmp" "$menu"; then
  echo "already up to date"
else
  if ((existed)); then
    backup="$menu.bak.$(date +%s)"
    cp "$menu" "$backup"
    echo "updated (backup: $backup)"
  else
    echo "created"
  fi
  cat "$tmp" >"$menu"
fi

echo
echo "sp11-touchscreen: done. Omarchy menu > Triggers > Hardware > Disable Touchscreen now turns finger touch off."
echo "From a terminal: surface-touchscreen on|off|toggle"
