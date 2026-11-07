# Toolbox for remastering the Omarchy aarch64 ISO (runs natively on the arm64 host).
# Debian trixie: systemd-ukify 257, xorriso, squashfs-tools, dtc, gnupg.
FROM debian:trixie-slim
RUN apt-get update \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
      systemd-ukify python3 xorriso squashfs-tools device-tree-compiler \
      gnupg curl ca-certificates zstd xz-utils util-linux \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /work
