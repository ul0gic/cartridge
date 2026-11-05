#!/usr/bin/env python3
import os
import re
import subprocess
import sys
import tarfile
from pathlib import Path

from download import fetch

RAW = "https://raw.githubusercontent.com/"
MAX_LICENSE_BYTES = 1 << 20
LICENSES = {
    "mesen": "libretro/Mesen/master/LICENSE",
    "snes9x": "libretro/snes9x/master/LICENSE",
    "genesis-plus-gx": "libretro/Genesis-Plus-GX/master/LICENSE.txt",
    "mupen64plus-next": "libretro/mupen64plus-libretro-nx/master/LICENSE",
    "beetle-psx": "libretro/beetle-psx-libretro/master/COPYING",
    "libretro-database": "libretro/libretro-database/master/LICENSE",
    "xemu": "xemu-project/xemu/v0.8.139/COPYING",
}

ROOT = Path(__file__).resolve().parent.parent.parent
XEMU_WORK = ROOT / ".build" / "xemu"
XEMU_SRC = XEMU_WORK / "src"
MACPORTS = XEMU_WORK / "macos-libs" / "arm64"
FATX_COMMIT = "4fd8e81324d67f734dbfd3606f78f6981ff30d51"
DSP56300_TARBALL = "dsp56300-0.1.3-aarch64-apple-darwin"
THIRD_PARTY_START = "xemu depends on several great packages/libraries"


def banner(name):
    # xemu scripts/gen-license.py banner(): 80 columns of dashes around the name.
    mid = len(name) + 2
    left = (80 - mid) // 2
    return "-" * left + " " + name + " " + "-" * (80 - mid - left)


def entry(name, url, version, text):
    lines = [banner(name), "", "Project URL:      " + url, "Version Included: " + version, "Project License:", ""]
    lines += [" | " + line for line in text.splitlines()]
    return "\n".join(lines) + "\n\n"


def wrap_git(name):
    text = (XEMU_SRC / "subprojects" / (name + ".wrap")).read_text()
    url = re.search(r"^url\s*=\s*(\S+)", text, re.MULTILINE).group(1)
    revision = re.search(r"^revision\s*=\s*(\S+)", text, re.MULTILINE).group(1)
    return url.removesuffix(".git"), revision


def macports_versions():
    lines = (MACPORTS / "INSTALLED").read_text().splitlines()
    return dict(line.strip().split("=", 1) for line in lines if line.strip())


def xemu_third_party():
    if not (XEMU_WORK / "build" / "build.ninja").exists():
        sys.exit("xemu: %s has not been built; run Cartridge/Xemu/build-xemu.sh" % XEMU_SRC)

    env = dict(os.environ, PKG_CONFIG_LIBDIR=str(MACPORTS / "opt" / "local" / "lib" / "pkgconfig"))
    generated = subprocess.run(
        [sys.executable, "scripts/gen-license.py", "--platform", "darwin",
         "--version-file=../macos-libs/arm64/INSTALLED"],
        cwd=XEMU_SRC, env=env, capture_output=True, check=True,
    ).stdout.decode("utf-8")
    text = generated[generated.index(THIRD_PARTY_START):]

    versions = macports_versions()
    subprojects = XEMU_SRC / "subprojects"
    text += entry("libcurl", "https://curl.se/", "8.12.1",
                  (subprojects / "curl-8.12.1" / "COPYING").read_text())
    libusb = versions["libusb"]
    libusb_copying = fetch(RAW + "libusb/libusb/v%s/COPYING" % libusb.split("_")[0], MAX_LICENSE_BYTES)
    text += entry("libusb", "https://libusb.info/", libusb, libusb_copying.decode("utf-8"))
    text += entry("libpcap", "https://www.tcpdump.org/", versions["libpcap"],
                  (MACPORTS / "opt" / "local" / "share" / "doc" / "libpcap" / "LICENSE").read_text())
    url, revision = wrap_git("genconfig")
    text += entry("genconfig", url, revision, (subprojects / "genconfig" / "LICENSE.txt").read_text())
    url, revision = wrap_git("keycodemapdb")
    keycodemapdb = subprojects / "keycodemapdb"
    text += entry("keycodemapdb", url, revision,
                  (keycodemapdb / "LICENSE.BSD").read_text() + "\n" + (keycodemapdb / "LICENSE.GPL2").read_text())
    url, revision = wrap_git("nlohmann_json")
    text += entry("nlohmann_json", url, revision, (subprojects / "nlohmann_json" / "LICENSE.MIT").read_text())
    text += entry("libfatx", "https://github.com/XboxDev/fatx", FATX_COMMIT,
                  (XEMU_WORK / "fatx" / "LICENSE.txt").read_text())
    with tarfile.open(subprojects / "dsp56300" / (DSP56300_TARBALL + ".tar.gz")) as tar:
        crates = tar.extractfile(DSP56300_TARBALL + "/THIRDPARTY-emu").read().decode("utf-8")
    text += entry("dsp56300 crate dependencies", "https://github.com/mborgerson/dsp56300", "0.1.3", crates)
    return text


def main():
    names = sys.argv[1:] or list(LICENSES)
    unknown = [name for name in names if name not in LICENSES]
    if unknown:
        sys.exit("unknown licence: %s" % ", ".join(unknown))
    dest = ROOT / "Cartridge" / "App" / "Resources" / "Licenses"
    dest.mkdir(parents=True, exist_ok=True)
    for name in names:
        text = fetch(RAW + LICENSES[name], MAX_LICENSE_BYTES)
        if not text.strip():
            sys.exit("%s: downloaded licence is empty" % name)
        if name == "xemu":
            text += ("\n" + xemu_third_party()).encode("utf-8")
        (dest / (name + ".txt")).write_bytes(text)
        print("%-20s %7d bytes" % (name, len(text)))


if __name__ == "__main__":
    main()
