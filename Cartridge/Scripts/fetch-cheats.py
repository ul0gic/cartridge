#!/usr/bin/env python3
import datetime
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

REPOSITORY = "https://github.com/libretro/libretro-database.git"
COMMIT = "12c21cf79f1e20eff6ac68b80875816c717d0a7a"
FOLDERS = [
    "Nintendo - Nintendo Entertainment System",
    "Nintendo - Super Nintendo Entertainment System",
    "Sega - Mega Drive - Genesis",
    "Nintendo - Nintendo 64",
    "Sony - PlayStation",
]


def git(checkout, *arguments):
    result = subprocess.run(["git", *arguments], cwd=checkout, check=True, capture_output=True, text=True)
    return result.stdout.strip()


def fetch(checkout):
    git(checkout, "init", "--quiet")
    git(checkout, "remote", "add", "origin", REPOSITORY)
    git(checkout, "sparse-checkout", "set", *("cht/" + folder for folder in FOLDERS))
    git(checkout, "fetch", "--quiet", "--depth", "1", "--filter=blob:none", "origin", COMMIT)
    git(checkout, "checkout", "--quiet", "FETCH_HEAD")
    head = git(checkout, "rev-parse", "HEAD")
    if head != COMMIT:
        sys.exit("checked out %s, expected %s" % (head, COMMIT))
    return git(checkout, "show", "-s", "--format=%cs", "HEAD")


def copy_folder(source, dest):
    if dest.exists():
        shutil.rmtree(dest)
    dest.mkdir(parents=True)
    count = 0
    size = 0
    for path in sorted(source.iterdir()):
        if path.name.endswith(".cht") and path.is_file() and not path.is_symlink():
            shutil.copyfile(path, dest / path.name)
            count += 1
            size += path.stat().st_size
    if count == 0:
        sys.exit("%s: no .cht files at %s" % (source.name, COMMIT))
    return count, size


def write_record(dest, commit_date, counts):
    total_files = sum(count for count, _ in counts.values())
    total_bytes = sum(size for _, size in counts.values())
    lines = [
        "# Cheats",
        "",
        "Verbatim `.cht` files from [libretro-database](%s), written by `Cartridge/Scripts/fetch-cheats.py`."
        % REPOSITORY[: -len(".git")],
        "",
        "- Commit: `%s` (%s)" % (COMMIT, commit_date),
        "- Fetched: %s" % datetime.date.today().isoformat(),
        "- Files: %d" % total_files,
        "- Bytes: %d" % total_bytes,
        "",
        "| Folder | Files | Bytes |",
        "|--------|-------|-------|",
    ]
    lines += ["| %s | %d | %d |" % (folder, count, size) for folder, (count, size) in counts.items()]
    (dest / "CHEATS.md").write_text("\n".join(lines) + "\n")


def main():
    dest = Path(__file__).resolve().parent.parent / "App" / "Resources" / "Cheats"
    counts = {}
    with tempfile.TemporaryDirectory() as checkout:
        commit_date = fetch(checkout)
        for folder in FOLDERS:
            counts[folder] = copy_folder(Path(checkout) / "cht" / folder, dest / folder)
            print("%-48s %5d files %10d bytes" % (folder, *counts[folder]))
    write_record(dest, commit_date, counts)


if __name__ == "__main__":
    main()
