#!/usr/bin/env python3
import json
import re
import sys
from pathlib import Path
from urllib.parse import quote

from download import fetch

RAW = "https://raw.githubusercontent.com/libretro/libretro-database/master/metadat/"
MAX_DAT_BYTES = 32 << 20
LICENSE = "CC BY-SA 4.0 (libretro-database, https://github.com/libretro/libretro-database)"

SYSTEMS = {
    "nes": ("no-intro", "Nintendo - Nintendo Entertainment System", "byCRC"),
    "snes": ("no-intro", "Nintendo - Super Nintendo Entertainment System", "byCRC"),
    "genesis": ("no-intro", "Sega - Mega Drive - Genesis", "byCRC"),
    "n64": ("no-intro", "Nintendo - Nintendo 64", "byCRC"),
    "ps1": ("redump", "Sony - PlayStation", "bySerial"),
    "xbox": ("redump", "Microsoft - Xbox", "bySerial"),
}
SYSTEMS_WITHOUT_META = {"xbox"}

VERSION = re.compile(r'^\s*version "([^"]+)"', re.MULTILINE)
GAME_NAME = re.compile(r'^\s*name "((?:[^"\\]|\\.)*)"', re.MULTILINE)
GAME_SERIAL = re.compile(r'^\s*serial "([^"]+)"', re.MULTILINE)
ROM_CRC = re.compile(r"\brom \(.*?\bcrc ([0-9A-Fa-f]{8})\b")
ESCAPE = re.compile(r"\\(.)")
PARENTHETICAL = re.compile(r"\([^)]*\)")
USA_OR_WORLD = ("(USA", "(World)")

CRC_META_FIELDS = {
    "genre": ("genre", "genre"),
    "releaseyear": ("releaseyear", "year"),
    "developer": ("developer", "developer"),
    "publisher": ("publisher", "publisher"),
    "maxusers": ("users", "players"),
}
SERIAL_META_FIELDS = {
    "genre": "genre",
    "releaseyear": "year",
    "developer": "developer",
    "publisher": "publisher",
    "users": "players",
    "description": "summary",
}
NUMERIC_META = {"year", "players"}
PS1_META_DAT = "developer"


def games(text):
    for block in text.split("\ngame (\n")[1:]:
        body = block.split("\n)\n", 1)[0]
        name = GAME_NAME.search(body)
        if name:
            yield name.group(1), body


def index_by_crc(text):
    index = {}
    for name, body in games(text):
        for crc in ROM_CRC.findall(body):
            index.setdefault(crc.upper(), name)
    return index


def index_by_serial(text):
    index = {}
    for name, body in games(text):
        serial = GAME_SERIAL.search(body)
        if serial:
            index.setdefault(serial.group(1).upper(), name)
    return index


def index_by_usa_world_serial(text):
    chosen = {}
    for name, body in games(text):
        serial = GAME_SERIAL.search(body)
        if not serial or not any(tag in name for tag in USA_OR_WORLD):
            continue
        key = serial.group(1).upper()
        rank = (len(PARENTHETICAL.findall(name)), len(name), name)
        if key not in chosen or rank < chosen[key][0]:
            chosen[key] = (rank, name)
    return {key: name for key, (_, name) in chosen.items()}


def blocks(text):
    for block in text.split("\ngame (\n")[1:]:
        yield block.split("\n)\n", 1)[0]


def meta_value(body, field, name):
    match = re.search(r'^\s*%s "?((?:[^"\\\n]|\\.)*)"?\s*$' % field, body, re.MULTILINE)
    if not match:
        return None
    value = ESCAPE.sub(r"\1", match.group(1)).strip()
    if name in NUMERIC_META:
        return int(value) if value.isdigit() else None
    return value or None


def meta_by_crc(folder, keys):
    meta = {}
    for dat, (field, name) in CRC_META_FIELDS.items():
        url = "%s%s/%s.dat" % (RAW, dat, quote(folder))
        text = fetch(url, MAX_DAT_BYTES).decode("utf-8")
        for body in blocks(text):
            value = meta_value(body, field, name)
            if value is None:
                continue
            for crc in ROM_CRC.findall(body):
                if crc.upper() in keys:
                    meta.setdefault(crc.upper(), {}).setdefault(name, value)
    return share_by_name(keys, meta)


def share_by_name(index, meta):
    by_name = {}
    for key, name in index.items():
        if key in meta:
            by_name.setdefault(name, meta[key])
    for key, name in index.items():
        if key not in meta and name in by_name:
            meta[key] = by_name[name]
    return meta


def meta_by_serial(folder, keys):
    url = "%s%s/%s.dat" % (RAW, PS1_META_DAT, quote(folder))
    text = fetch(url, MAX_DAT_BYTES).decode("utf-8")
    meta = {}
    for body in blocks(text):
        serial = GAME_SERIAL.search(body)
        if not serial or serial.group(1).upper() not in keys:
            continue
        entry = {}
        for field, name in SERIAL_META_FIELDS.items():
            value = meta_value(body, field, name)
            if value is not None:
                entry[name] = value
        if entry:
            meta.setdefault(serial.group(1).upper(), entry)
    return meta


def main():
    requested = sys.argv[1:]
    unknown = [system for system in requested if system not in SYSTEMS]
    if unknown:
        sys.exit("unknown systems: %s (known: %s)" % (", ".join(unknown), ", ".join(SYSTEMS)))
    dest = Path(__file__).resolve().parent.parent / "App" / "Resources" / "Database"
    dest.mkdir(parents=True, exist_ok=True)
    for system, (source, folder, key) in SYSTEMS.items():
        if requested and system not in requested:
            continue
        url = "%s%s/%s.dat" % (RAW, source, quote(folder))
        text = fetch(url, MAX_DAT_BYTES).decode("utf-8")
        version = VERSION.search(text)
        if not version:
            sys.exit("%s: no version in the dat header" % url)
        if system == "xbox":
            index = index_by_usa_world_serial(text)
        else:
            index = (index_by_serial if key == "bySerial" else index_by_crc)(text)
        if not index:
            sys.exit("%s: no entries parsed" % url)
        if system in SYSTEMS_WITHOUT_META:
            meta = {}
        else:
            meta = meta_by_serial(folder, index) if key == "bySerial" else meta_by_crc(folder, index)
        document = {
            "system": system,
            "source": "%s (version %s)" % (url, version.group(1)),
            "license": LICENSE,
            key: index,
            "meta": meta,
        }
        (dest / (system + ".json")).write_text(json.dumps(document, sort_keys=True, separators=(",", ":")) + "\n")
        print("%-8s %6d entries, %6d with metadata, dat %s" % (system, len(index), len(meta), version.group(1)))


if __name__ == "__main__":
    main()
