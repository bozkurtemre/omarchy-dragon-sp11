# Toolbox for verify-edge-iso.sh: the Arch Linux ARM image omarchy-iso builds
# its aarch64 ISO in (bin/omarchy-iso-make, pinned by digest), with the tools
# from Omarchy's ARM mirror for edge, the one that build installs from.
FROM ghcr.io/menci/archlinuxarm@sha256:3e1074c407fc1a57c2a2117af6920c96a7cc906fa6f1f2da8a4a7fd3aa2c2f4e
# pacman 7 sandboxes its downloads with Landlock, which WSL2's kernel lacks;
# omarchy-iso's build-iso.sh uses the same wrapper there.
RUN printf '#!/bin/sh\nexec /usr/bin/pacman --disable-sandbox "$@"\n' >/usr/local/bin/pacman \
 && chmod +x /usr/local/bin/pacman \
 && echo 'Server = https://arm-mirror.omarchy.org/$arch/$repo' >/etc/pacman.d/mirrorlist \
 && pacman-key --init \
 && pacman --noconfirm -Sy archlinuxarm-keyring \
 && pacman-key --populate archlinuxarm \
 && pacman --noconfirm -Syu libisoburn squashfs-tools python mkinitcpio zstd dtc libarchive util-linux \
 && pacman --noconfirm -Scc
WORKDIR /work
