#!/usr/bin/env python3
import argparse
import hashlib
import io
import re
import sys
import zipfile
from pathlib import Path

from download import fetch

MAX_ARCHIVE_BYTES = 64 << 20
MAX_DYLIB_BYTES = 128 << 20
ROW = re.compile(r"^\| (\S+\.dylib) \| (https://\S+) \| ([0-9a-f]{64}) \|$")


def read_manifest(path):
    rows = [m.groups() for m in map(ROW.match, path.read_text().splitlines()) if m]
    if not rows:
        raise SystemExit("no core rows in %s" % path)
    return rows


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def main():
    cores = Path(__file__).resolve().parent.parent / "Cores"
    parser = argparse.ArgumentParser(description="Download the bundled libretro cores and verify them against CORES.md")
    parser.add_argument("--dest", type=Path, default=cores, help="directory to write the dylibs into")
    args = parser.parse_args()

    args.dest.mkdir(parents=True, exist_ok=True)
    failures = []
    for name, url, expected in read_manifest(cores / "CORES.md"):
        target = args.dest / name
        if target.exists() and sha256(target.read_bytes()) == expected:
            print("ok      %s" % name)
            continue
        with zipfile.ZipFile(io.BytesIO(fetch(url, MAX_ARCHIVE_BYTES))) as archive:
            info = archive.getinfo(name)
            if info.file_size > MAX_DYLIB_BYTES:
                raise SystemExit("%s: %d bytes exceeds the limit" % (name, info.file_size))
            data = archive.read(info)
        actual = sha256(data)
        if actual != expected:
            failures.append(name)
            print("MISMATCH %s: CORES.md %s, downloaded %s" % (name, expected, actual))
            continue
        target.write_bytes(data)
        print("fetched %s" % name)
    if failures:
        sys.exit("%d core(s) differ from CORES.md; the buildbot 'latest' build changed" % len(failures))


if __name__ == "__main__":
    main()
