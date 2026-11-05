# xemu

xemu 0.8.139 (tag `v0.8.139`, commit `aa54c34cae1c09410d74c69a44210a9867fe2d16`, https://github.com/xemu-project/xemu, GPL-2.0) built from source into `libxemu.dylib` behind `include/cartridge_xemu.h`. libfatx from XboxDev/fatx (commit `4fd8e81324d67f734dbfd3606f78f6981ff30d51`, https://github.com/XboxDev/fatx, GPL-2.0) is compiled into the library. Licence text: `Cartridge/App/Resources/Licenses/xemu.txt` (xemu's `COPYING` at the tag).

## Patches

Applied in name order by `build-xemu.sh`; every file they change or add carries a dated ul0gic change notice.

| File | About name |
|---|---|
| `patches/0001-nv2a-depth-precision-fast-path.patch` | Depth-precision fast path (catskull c5fa9ff4) |
| `patches/0002-build-as-shared-library.patch` | Shared-library build |
| `patches/0003-cartridge-headless-host.patch` | Headless host: display, input and audio for Cartridge |
| `patches/0004-dvd-partition-offset.patch` | Redump discs read in place |
| `patches/0005-apu-reset-keeps-frame-thread-paused.patch` | APU reset while the VM is stopped leaves the frame thread paused (snapshot restore from `-S`) |
| `patches/fatx/0001-kernel-e-partition-size.patch` | libfatx: retail E partition size |

`overlay/` holds the files Cartridge adds to the tree (CGL contexts, the C ABI entry, display, drives and input).

## Build

```sh
PYTHON=/opt/homebrew/opt/python@3.13/bin/python3.13 Cartridge/Xemu/build-xemu.sh
```

Needs `ninja`, `pkgconf`, `cmake`, Python 3.13 with PyYAML, and network to github.com and packages.macports.org. Python 3.14 and later refuse the MacPorts archives (tarfile `data` filter). Outputs: `Products/` (gitignored) and `.build/xemu-tools/qemu-img` (development checks only).

MacPorts packages for the build of 2026-11-01 (`.build/xemu/macos-libs/arm64/INSTALLED`): SDL3 3.4.8_0, glib2 2.88.3_2, libsamplerate 0.2.2_0, libpixman 0.46.0_0, libepoxy 1.5.10_4, libpcap 1.11.0_0, libslirp 4.9.1_0, libusb 1.0.30_0, gettext-runtime 1.0_0, libiconv 1.19_0, pcre2 10.49_0, zlib 1.3.2_0 and their dependencies.

## Products

Built 2026-11-05 (ad-hoc signed; re-signed by `Cartridge/Scripts/embed-xemu.sh`).

| File | SHA-256 |
|---|---|
| libxemu.dylib | 32c4577b1f44eeb6320e276f938fa158756e1356066f09cf5e30427b624f3454 |
| libSDL3.0.dylib | 55b9a3041de3b38e6e0a2227557966f614e106ef8e6ed35f6c94b62e987a295f |
| libepoxy.0.dylib | a79f3599eaabfe68b8ce22ac26494b7a0c333158932b223b82093e12e3cb991a |
| libglib-2.0.0.dylib | e7c09b1b0c7d6cde9a6d015dc3815bb702000d2a9eabb3e62a441978a4d07bb7 |
| libiconv.2.dylib | 5015c8d0fe64131bc2a28e095352ea920671d8d3f469835295196655c0a0dad0 |
| libintl.8.dylib | 06b4af0619498af069356af17587f4e9bf612ada001d4bfe6758d905e3b29f03 |
| libpcap.A.dylib | 125d9342ac273701b6c401ab764524d2d086337a6d141545933d4ad522e3c7e9 |
| libpcre2-8.0.dylib | a5dd35f2867737b08d27a9af22c92005359a632b8258aec4f82c781ec63b4648 |
| libsamplerate.0.dylib | fc2b785bce25d4adb02fef64974c82aab7bd927ec9d155f46c7c70106b1e215d |
| libslirp.0.dylib | d1372da3799a96eed89c678de10da64bdd56e11df58a1997455d389466a88401 |
| libusb-1.0.0.dylib | 974c8880c418d5c8d785b8c1fc4e9a3de96300c7ea917d7222b45c1b1b674638 |
| libz.1.dylib | 59236e13c504e39e2482c8f29eae049bc7b092d375aeeda133caa051a463bd46 |

## Source archive

`Cartridge/Xemu/make-source-archive.sh dist/Cartridge-<version>-xemu-src.tar.gz` runs after `build-xemu.sh` and needs cargo (rustup) and network to github.com, crates.io and distfiles.macports.org. Publish the archive wherever the app zip is published, for as long as the zip is offered. The archive holds:

- `xemu/`: the tree at the commit above, with `subprojects/` holding the nine directories the build fetched (`curl-8.12.1`, `genconfig`, `imgui`, `implot`, `keycodemapdb`, `nlohmann_json`, `nv2a_vsh_cpu`, `tomlplusplus`, `xxHash-0.8.3`), without `.git`
- `fatx/`: the fatx tree at the commit above
- `dsp56300/`: dsp56300 v0.1.3 (commit `bde7c233a447d32d558c48cb4438e1425fe0bbcc`, https://github.com/mborgerson/dsp56300, MIT) with every crate it uses in `vendor/` and `.cargo/config.toml` pointing cargo at them
- `macports/`: for each dylib in `Products/` other than `libxemu.dylib`, the MacPorts port's byte-identical distfile, its as-built Portfile and its `files/` patches, plus `SOURCES.md` (dylib, version, licence, distfile, SHA-256, patches, macports-ports commit, install command, rebuild steps) and `SHA256SUMS`. The committed copies are in `Cartridge/Xemu/macports/`. The script fails if a distfile's hash differs, if `INSTALLED` no longer matches `SOURCES.md`, or if a dylib in `Products/` has no row
- `cartridge/`: `patches/`, `overlay/`, `include/`, `build-xemu.sh`, `cartridge_xemu.exports` and this file

Apart from the MacPorts distfiles, which are upstream source tarballs, the archive holds no archive files and no prebuilt binaries. To rebuild offline:

1. In `dsp56300/`, run `cargo build --release --offline --target aarch64-apple-darwin --workspace` (toolchain 1.96.0 from its `rust-toolchain.toml`).
2. Stage `lib/libdsp56300_emu_ffi.a`, `include/dsp56300.h` (from `crates/emu-ffi/include/`), the `bin/` tools and `LICENSE` in a folder named `dsp56300-0.1.3-aarch64-apple-darwin`, as its `.github/workflows/ci.yml:125-148` does. Its `THIRDPARTY-*` notices come from `cargo about` and the build does not read them. Tar it as `dsp56300-0.1.3-aarch64-apple-darwin.tar.gz` into `xemu/subprojects/dsp56300/`; its `meson.build` then uses that file instead of downloading it.
3. Apply `cartridge/patches/fatx/*.patch` to `fatx/` and `cartridge/patches/*.patch` to `xemu/` in name order, copy `cartridge/overlay/` over `xemu/`, then copy `cartridge/include/cartridge_xemu.h`, `cartridge/cartridge_xemu.exports` and `fatx/libfatx/*.{c,h}` (into `ui/cartridge/libfatx/`) as `build-xemu.sh` does.
4. Configure and build with the options in `build-xemu.sh`. The MacPorts libraries it links are listed under Build.
