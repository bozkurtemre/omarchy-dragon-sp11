#!/usr/bin/env python3
"""Unflatten a DTB into a /sys/firmware/devicetree/base-style directory.

Usage: dtb2fs.py DTB OUTDIR (test aid for qcom-firmware-extract, which reads the running device tree).
"""
import struct
import sys
from pathlib import Path

dtb = Path(sys.argv[1]).read_bytes()
root = Path(sys.argv[2])
magic, _size, off_struct, off_strings = struct.unpack_from(">4I", dtb, 0)
assert magic == 0xD00DFEED
pos, path = off_struct, []
while True:
    token, = struct.unpack_from(">I", dtb, pos)
    pos += 4
    if token == 1:
        end = dtb.index(b"\0", pos)
        name = dtb[pos:end].decode()
        pos = (end + 4) & ~3
        path.append(name)
        root.joinpath(*path[1:]).mkdir(parents=True, exist_ok=True)
    elif token == 2:
        path.pop()
    elif token == 3:
        length, name_off = struct.unpack_from(">II", dtb, pos)
        pos += 8
        start = off_strings + name_off
        name = dtb[start:dtb.index(b"\0", start)].decode()
        root.joinpath(*path[1:], name).write_bytes(dtb[pos:pos + length])
        pos = (pos + length + 3) & ~3
    elif token == 4:
        continue
    else:
        break
