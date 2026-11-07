#!/usr/bin/env python3
"""Inspect the device trees inside a UKI (no third-party modules).

  uki-dtb.py split UKI OUTDIR   write every PE section to OUTDIR (".dtbauto"
                                copies get an index) and print each device
                                tree's file name and first compatible
  uki-dtb.py check UKI COMPAT   exit 0 only if the UKI carries exactly one
                                .dtb, its first compatible is COMPAT, and it
                                has no .dtbauto/.hwids section that
                                systemd-stub would prefer over it

systemd-stub matches device trees on the first compatible string only
(src/boot/devicetree.c), and a matching .dtbauto wins over .dtb
(src/boot/stub.c), so those are the properties that decide what boots.
"""
import struct
import sys
from pathlib import Path


def sections(image: bytes):
    """Yield (name, payload) for every PE section, in table order."""
    if image[:2] != b"MZ":
        raise ValueError("not a PE image")
    pe = struct.unpack_from("<I", image, 0x3C)[0]
    if image[pe:pe + 4] != b"PE\0\0":
        raise ValueError("missing PE signature")
    count, = struct.unpack_from("<H", image, pe + 6)
    optional_size, = struct.unpack_from("<H", image, pe + 20)
    table = pe + 24 + optional_size
    for i in range(count):
        entry = table + 40 * i
        name = image[entry:entry + 8].rstrip(b"\0").decode()
        virtual_size, _addr, raw_size, raw_offset = struct.unpack_from("<IIII", image, entry + 8)
        # VirtualSize is the payload length; raw data is padded to FileAlignment.
        yield name, image[raw_offset:raw_offset + min(virtual_size or raw_size, raw_size)]


def first_compatible(dtb: bytes):
    """Return the root node's first compatible string of a flattened DT."""
    magic, _size, off_struct, off_strings = struct.unpack_from(">4I", dtb, 0)
    if magic != 0xD00DFEED:
        return None
    pos, depth = off_struct, 0
    while pos + 4 <= len(dtb):
        token, = struct.unpack_from(">I", dtb, pos)
        pos += 4
        if token == 1:  # FDT_BEGIN_NODE
            pos = (dtb.index(b"\0", pos) + 4) & ~3
            depth += 1
        elif token == 2:  # FDT_END_NODE
            depth -= 1
        elif token == 3:  # FDT_PROP
            length, name_off = struct.unpack_from(">II", dtb, pos)
            pos += 8
            start = off_strings + name_off
            if depth == 1 and dtb[start:dtb.index(b"\0", start)] == b"compatible":
                return dtb[pos:pos + length].split(b"\0")[0].decode()
            pos = (pos + length + 3) & ~3
        elif token == 4:  # FDT_NOP
            continue
        else:  # FDT_END or garbage
            break
    return None


def split(uki: Path, outdir: Path) -> None:
    outdir.mkdir(parents=True, exist_ok=True)
    seen: dict[str, int] = {}
    for name, data in sections(uki.read_bytes()):
        index = seen.get(name, 0)
        seen[name] = index + 1
        target = outdir / (f"{name}.{index}" if name == ".dtbauto" else name)
        target.write_bytes(data)
        if name in (".dtb", ".dtbauto"):
            print(f"{target.name}\t{first_compatible(data)}")


def check(uki: Path, compat: str) -> int:
    found = list(sections(uki.read_bytes()))
    names = [name for name, _ in found]
    dtbs = [first_compatible(data) for name, data in found if name == ".dtb"]
    problems = []
    if ".linux" not in names:
        problems.append("no .linux section (not a UKI)")
    if dtbs != [compat]:
        problems.append(f".dtb sections carry {dtbs or 'nothing'}, expected exactly [{compat!r}]")
    for unwanted in (".dtbauto", ".hwids"):
        if unwanted in names:
            problems.append(f"has {names.count(unwanted)} {unwanted} section(s); systemd-stub may pick another tree")
    for problem in problems:
        print(f"{uki}: {problem}", file=sys.stderr)
    if not problems:
        print(f"{uki}: OK, boots {compat}")
    return 1 if problems else 0


def main() -> int:
    if len(sys.argv) == 4 and sys.argv[1] == "split":
        split(Path(sys.argv[2]), Path(sys.argv[3]))
        return 0
    if len(sys.argv) == 4 and sys.argv[1] == "check":
        return check(Path(sys.argv[2]), sys.argv[3])
    print(__doc__, file=sys.stderr)
    return 2


sys.exit(main())
