# MacPorts sources

The dylibs beside `libxemu.dylib` in `Cartridge/Xemu/Products/` are prebuilt MacPorts packages, downloaded by xemu's `scripts/download-macos-libs.py` for darwin 23 arm64. Each folder here holds the package's as-built Portfile (`+PORTFILE` from its `.tbz2` in `.build/xemu/macos-pkgs/`) and the `files/` patches that Portfile applies on darwin. Every Portfile here is byte-identical to the macports-ports tree at the listed commit. That commit is the package's `@ports_commit`, except libsamplerate, whose package records none; there it is the commit whose Portfile matches. `make-source-archive.sh` reads the table below, downloads each distfile, checks its SHA-256 against this table and the Portfile's `checksums`, and writes `macports/SHA256SUMS` (ADR-0037).

| Dylib | Package (INSTALLED) | Licence | Distfile | SHA-256 | Patches | macports-ports commit | Install |
|---|---|---|---|---|---|---|---|
| libSDL3.0.dylib | SDL3=3.4.8_0 | Zlib | https://distfiles.macports.org/SDL3/SDL3-3.4.8.tar.gz | e9fff7467fb60f037e6708da18b25560649e4c63edc2a69bb871b960d9cbfbba | none | 539f06379ec68ece3813f79d49ee11c5902f5a15 devel/SDL3 | sudo port install SDL3 |
| libepoxy.0.dylib | libepoxy=1.5.10_4+x11 | MIT | https://distfiles.macports.org/libepoxy/libepoxy-1.5.10.tar.gz | b3e076c5bea209ffa7789cb460d76718be206ccad65a8c915757957c76318376 | 5 in files/ | f1d80e565540712e5e6f2335b1f945750428ef95 graphics/libepoxy | sudo port install libepoxy +x11 |
| libglib-2.0.0.dylib | glib2=2.88.3_2+dbus+x11 | LGPL-2.1-or-later | https://distfiles.macports.org/glib2/glib-2.88.3.tar.xz | ab24d24e698dfa1e408b7bcdb508f4aafc906185a8b8ce72fdf79bbbdc9b383b | 15 in files/ | a702f9b726d2a48092eed32bec5191d4499c74ff devel/glib2 | sudo port install glib2 +dbus +x11 |
| libiconv.2.dylib | libiconv=1.19_0 | LGPL-2.1-or-later | https://distfiles.macports.org/libiconv/libiconv-1.19.tar.gz | 88dd96a8c0464eca144fc791ae60cd31cd8ee78321e67397e25fc095c4a19aa6 | 2 in files/ | 03b1b44cce27fbd3fee6686d4b107bcd621940c1 textproc/libiconv | sudo port install libiconv |
| libintl.8.dylib | gettext-runtime=1.0_0 | LGPL-2.1-or-later | https://distfiles.macports.org/gettext/gettext-1.0.tar.xz | 71132a3fb71e68245b8f2ac4e9e97137d3e5c02f415636eb508ae607bc01add7 | 1 in files/ | 745ff1b58358f448da09339ba9c3ea3a464e773e devel/gettext | sudo port install gettext-runtime |
| libpcap.A.dylib | libpcap=1.11.0_0 | BSD-3-Clause | https://distfiles.macports.org/libpcap/libpcap-1.11.0.tar.gz | 596389bc8560ea027dff9db8aaf6c173d992366d9aef4baf5d7c6d180b4d49ad | none | 18ea1cc47010c76482df165e29ef4127ec05d810 net/libpcap | sudo port install libpcap |
| libpcre2-8.0.dylib | pcre2=10.49_0 | BSD-3-Clause | https://distfiles.macports.org/pcre/pcre2-10.49.tar.bz2 | 53c156e1ba416a20da8e65395daa132da0d80e76910424caca3fcdae7831d384 | none | 8cd924b447c30b25649d6e2a6e1553ce98f9fa16 devel/pcre | sudo port install pcre2 |
| libsamplerate.0.dylib | libsamplerate=0.2.2_0 | BSD-2-Clause | https://distfiles.macports.org/libsamplerate/libsamplerate-0.2.2.tar.gz | 16e881487f184250deb4fcb60432d7556ab12cb58caea71ef23960aec6c0405a | none | 3fad2aabef17013f90b1d8fe61c0ddf0df378759 audio/libsamplerate | sudo port install libsamplerate |
| libslirp.0.dylib | libslirp=4.9.1_0 | BSD-3-Clause | https://distfiles.macports.org/libslirp/libslirp-4.9.1.tar.bz2 | 1bed745adf70f0a903c8101d6a3cd8beccbdf44ca05db1d60f290520b18e1fa4 | none | 62af9ac6fd34086d54ebf016c7773a22ae5f5cab net/libslirp | sudo port install libslirp |
| libusb-1.0.0.dylib | libusb=1.0.30_0 | LGPL-2.1-or-later | https://distfiles.macports.org/libusb/libusb-1.0.30.tar.bz2 | fea36f34f9156400209595e300840767ab1a385ede1dc7ee893015aea9c6dbaf | none | faeb690f717402eff2a6d1327b55ae60bac55c48 devel/libusb | sudo port install libusb |
| libz.1.dylib | zlib=1.3.2_0 | Zlib | https://distfiles.macports.org/zlib/zlib-1.3.2.tar.xz | d7a0654783a4da529d1bb793b7ad9c3318020af77667bcae35f95d0e42a792f3 | none | 745ff1b58358f448da09339ba9c3ea3a464e773e archivers/zlib | sudo port install zlib |

The packages' own licence labels are `LGPL-2+` (glib2), `{LGPL-2+ GPL-3+}` (libiconv), `{LGPL-2.1+ GPL-3+}` (gettext) and `BSD` (libpcap, pcre2, libsamplerate, libslirp). The Licence column follows the upstream sources (`research/lgpl-macports-dylibs-in-a-signed-mac-app.md`, takeaway 1). libiconv's and gettext's GPL-3 parts cover their programs, not the libraries shipped here.

pcre2's Portfile also lists `single_module.patch`, but only for its `pcre` subport, so it is not in `files/`. glib2's other patches apply only before darwin 11, so they are not in `files/` either.

## Rebuild

With MacPorts installed (macOS 14 or later, Apple silicon):

1. Copy each `macports/<port>/` folder to `<category>/<portdir>` (the last column of "macports-ports commit") inside a local ports tree, run `portindex` there, and list the tree in `${prefix}/etc/macports/sources.conf` above the default.
2. Put each distfile under `${prefix}/var/macports/distfiles/<folder>/`, where `<folder>` is the directory in its URL (for example `pcre/pcre2-10.49.tar.bz2`), so MacPorts builds without downloading.
3. Run the Install column's command for each port. A rebuilt dylib replaces the one in `XboxHost.xpc/Contents/Frameworks/` only after the bundle is re-signed with the builder's own identity (library validation).
