#!/usr/bin/env python3
"""Read a UKI's .hwids section and say which device tree systemd-stub picks.

  hwids.py dump SECTION              print every record: type, CHID, name, compatible
  hwids.py compare SECTION JSONDIR   exit 0 only if SECTION holds exactly the
                                     (CHID, name, compatible) records of the JSON
                                     files under JSONDIR (what ukify --hwids reads)
  hwids.py match SECTION [--panel ID] [--manufacturer ...] [...]
                                     compute this machine's CHIDs and walk them in
                                     systemd-stub's priority order

The section is what ukify builds from a hwids directory (systemd
src/ukify/ukify.py, parse_hwid_dir): packed records of
  uint32 descriptor   type in the top 4 bits, record size in the low 28
  EFI_GUID chid       16 bytes, EFI mixed-endian
  uint32 name_offset  from the start of the section
  uint32 compatible_offset
ended by a record whose descriptor is 0, then the NUL-terminated strings.

CHIDs follow tools/sp11-chid.ps1, which mirrors systemd src/fundamental/chid.c
and src/boot/chid.c: the stub fills only manufacturer, family, product name,
SKU, baseboard and the EDID panel ID, and chid_match() tries
EXTRA+2, EXTRA+1, EXTRA+0, 3, 6, 8, 10, 4, 5, 7, 9, 11 in that order, taking
the first record (in section order) whose CHID equals the machine's.
"""
import argparse
import hashlib
import json
import struct
import sys
import uuid
from pathlib import Path

TYPES = {1: "devicetree", 2: "uefi-fw"}

# The Surface Pro 11 LCD this project targets (README "Verified on this device").
DEFAULTS = {
    "manufacturer": "Microsoft Corporation",
    "family": "Surface",
    "product_name": "Microsoft Surface Pro, 11th Edition",
    "product_sku": "Surface_Pro_11th_Edition_2076",
    "bb_manufacturer": "Microsoft Corporation",
    "bb_product": "Microsoft Surface Pro, 11th Edition",
}

# Priority order and fields, as in tools/sp11-chid.ps1.
CHID_TABLE = [
    ("EXTRA+2", ("manufacturer", "product_sku", "panel")),
    ("EXTRA+1", ("manufacturer", "family", "panel")),
    ("EXTRA+0", ("manufacturer", "family", "product_name", "panel")),
    ("3", ("manufacturer", "family", "product_name", "product_sku", "bb_manufacturer", "bb_product")),
    ("6", ("manufacturer", "product_sku", "bb_manufacturer", "bb_product")),
    ("8", ("manufacturer", "product_name", "bb_manufacturer", "bb_product")),
    ("10", ("manufacturer", "family", "bb_manufacturer", "bb_product")),
    ("4", ("manufacturer", "family", "product_name", "product_sku")),
    ("5", ("manufacturer", "family", "product_name")),
    ("7", ("manufacturer", "product_sku")),
    ("9", ("manufacturer", "product_name")),
    ("11", ("manufacturer", "family")),
]
NAMESPACE = bytes([0x70, 0xFF, 0xD8, 0x12, 0x4C, 0x7F, 0x4C, 0x7D]) + bytes(8)


def records(section: bytes):
    """Yield (type, chid, name, compatible) for every record, in section order."""
    pos = 0
    while True:
        descriptor, = struct.unpack_from("<I", section, pos)
        if descriptor == 0:
            return
        size = descriptor & 0x0FFFFFFF
        if size < 28:
            raise ValueError(f"record at {pos} has size {size}")
        raw = section[pos + 4:pos + 20]
        name_off, compat_off = struct.unpack_from("<II", section, pos + 20)
        yield (TYPES.get(descriptor >> 28, str(descriptor >> 28)), str(uuid.UUID(bytes_le=raw)),
               cstring(section, name_off), cstring(section, compat_off))
        pos += size


def cstring(blob: bytes, offset: int) -> str:
    return blob[offset:blob.index(b"\0", offset)].decode()


def json_records(jsondir: Path):
    found = set()
    for path in sorted(jsondir.rglob("*.json")):
        data = json.loads(path.read_text(encoding="utf-8"))
        target = data.get("compatible") or data.get("fwid")
        for chid in data["hwids"]:
            found.add((data["type"], str(uuid.UUID(chid)), data["name"], target))
    return found


def chid(fields: dict, names) -> str:
    data = "&".join(fields[n] for n in names).encode("utf-16-le")
    h = bytearray(hashlib.sha1(NAMESPACE + data).digest()[:16])
    h[6] = (h[6] & 0x0F) | 0x50
    h[8] = (h[8] & 0x3F) | 0x80
    return str(uuid.UUID(bytes=bytes(h)))


def match(section: bytes, fields: dict) -> int:
    recs = [r for r in records(section) if r[0] == "devicetree"]
    winner = None
    for kind, names in CHID_TABLE:
        if "panel" in names and not fields.get("panel"):
            print(f"{kind:>8}: (no panel ID, not computed)")
            continue
        value = chid(fields, names)
        hits = [r for r in recs if r[1] == value]
        note = ", ".join(f"{r[3]} ({r[2]})" for r in hits) or "-"
        print(f"{kind:>8}: {value} {note}")
        if hits and winner is None:
            winner = (kind, hits[0])
    if winner:
        print(f"systemd-stub picks {winner[1][3]} via CHID {winner[0]} ({winner[1][2]})")
    else:
        print("systemd-stub finds no matching record; it boots without a .dtbauto tree")
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="cmd", required=True)
    p = sub.add_parser("dump")
    p.add_argument("section", type=Path)
    p = sub.add_parser("compare")
    p.add_argument("section", type=Path)
    p.add_argument("jsondir", type=Path)
    p = sub.add_parser("match")
    p.add_argument("section", type=Path)
    p.add_argument("--panel", default="")
    for key, value in DEFAULTS.items():
        p.add_argument("--" + key.replace("_", "-"), dest=key, default=value)
    args = parser.parse_args()
    section = args.section.read_bytes()

    if args.cmd == "dump":
        for rec in records(section):
            print("\t".join(rec))
        return 0
    if args.cmd == "compare":
        have = set(records(section))
        want = json_records(args.jsondir)
        for rec in sorted(want - have):
            print("missing from section:", "\t".join(rec))
        for rec in sorted(have - want):
            print("not in JSON:", "\t".join(rec))
        print(f"section {len(have)} records, JSON {len(want)} records:", "identical" if have == want else "DIFFERENT")
        return 0 if have == want else 1
    fields = {key: getattr(args, key) for key in DEFAULTS}
    fields["panel"] = args.panel
    return match(section, fields)


sys.exit(main())
