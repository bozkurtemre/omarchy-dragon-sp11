#!/usr/bin/env bash
# Build Omarchy's aarch64 edge ISO with upstream's own procedure, unmodified:
# omarchy-iso's bin/omarchy-iso-make --arch aarch64 --edge --no-boot-offer,
# the command its nightly workflow runs for the edge-aarch64 channel.
#
# omarchy-iso-make is a Linux host script that starts a privileged build
# container with bind mounts of its own checkout. On Docker Desktop (Windows,
# WSL2 backend) it runs here, inside docker:29-cli, with the Docker socket and
# the sp11work volume mounted at the path the daemon itself sees the volume,
# so those bind mounts resolve on the daemon side. HOME lives in the volume, so
# the offline mirror cache (~/.cache/omarchy/iso_edge_aarch64) persists there.
#
# Expects a clone of https://github.com/omacom/omarchy-iso.git (LF endings) at
# <volume>/edge/omarchy-iso and this script at <volume>/edge/bin/. From Git Bash:
#   export MSYS_NO_PATHCONV=1
#   docker run -d --name sp11-edge-driver \
#     -v /var/run/docker.sock:/var/run/docker.sock \
#     -v sp11work:/var/lib/docker/volumes/sp11work/_data \
#     -e OMARCHY_ISO_COMMIT=<full omarchy-iso commit> \
#     docker:29-cli sh -c 'apk add --no-cache -q bash git coreutils findutils grep sed gawk util-linux >/dev/null &&
#       exec bash /var/lib/docker/volumes/sp11work/_data/edge/bin/build-edge-iso.sh'
# The ISO lands in <volume>/edge/omarchy-iso/release/. Needs about 40 GB in the
# Docker data disk and several GB of downloads.
set -euo pipefail

vol=/var/lib/docker/volumes/sp11work/_data
work=$vol/edge
commit=${OMARCHY_ISO_COMMIT:?}

die() { echo "edge-driver: $*" >&2; exit 1; }

export HOME=$work/home
mkdir -p "$HOME" "$work/logs"
git config --global --add safe.directory '*'

cd "$work/omarchy-iso"
git fetch -q origin quattro
git checkout -q --detach "$commit"
[[ $(git rev-parse HEAD) == "$commit" ]] || die "HEAD is not $commit"
[[ -z $(git status --porcelain) ]] || die "the omarchy-iso checkout has local changes"
rm -f release/*.iso

echo "omarchy-iso $(git rev-parse HEAD) ($(git log -1 --format=%ci))"
echo "build start $(date -u +%FT%TZ)"
./bin/omarchy-iso-make --arch aarch64 --edge --no-boot-offer
echo "build end $(date -u +%FT%TZ)"
git submodule status
ls -l release/
