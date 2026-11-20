# Toolbox for build/remaster.sh (runs natively on the arm64 host).
# Debian trixie: xorriso, and for the -LcdOnlyUki fallback systemd-ukify 257 and squashfs-tools.
FROM debian:trixie-slim
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      xorriso python3 systemd-ukify squashfs-tools util-linux \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /work
