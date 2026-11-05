#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
    echo "usage: $0 dist/Cartridge-<version>-xemu-src.tar.gz" >&2
    exit 2
fi

xemu_commit="aa54c34cae1c09410d74c69a44210a9867fe2d16"
fatx_commit="4fd8e81324d67f734dbfd3606f78f6981ff30d51"
dsp56300_url="https://github.com/mborgerson/dsp56300.git"
dsp56300_commit="bde7c233a447d32d558c48cb4438e1425fe0bbcc"
subprojects="curl-8.12.1 genconfig imgui implot keycodemapdb nlohmann_json nv2a_vsh_cpu tomlplusplus xxHash-0.8.3"

xemu_dir="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$xemu_dir/../.." && pwd)"
work="$root/.build/xemu"
if [ ! -d "$(dirname "$1")" ]; then
    echo "error: $(dirname "$1") does not exist" >&2
    exit 1
fi
output="$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"
name="$(basename "$output" .tar.gz)"
staging="$work/archive"
dsp56300="$work/dsp56300"
distfiles="$work/distfiles"
installed="$work/macos-libs/arm64/INSTALLED"
sources="$xemu_dir/macports/SOURCES.md"
PATH="$HOME/.cargo/bin:$PATH"

if ! command -v cargo >/dev/null; then
    echo "error: cargo is missing; install rustup" >&2
    exit 1
fi

for tree in "$work/src" "$work/fatx"; do
    if [ ! -d "$tree/.git" ]; then
        echo "error: $tree is missing; run Cartridge/Xemu/build-xemu.sh first" >&2
        exit 1
    fi
done

fetched="$(git -C "$work/src" status --porcelain --ignored subprojects | sed -n 's/^!! subprojects\///p')"
for entry in $fetched; do
    case " $subprojects packagecache .wraplock dsp56300/dsp56300-0.1.3-aarch64-apple-darwin.tar.gz " in
        *" ${entry%/} "*) ;;
        *)
            echo "error: the build fetched subprojects/$entry, which the archive does not cover" >&2
            exit 1
            ;;
    esac
done
for sub in $subprojects; do
    if [ ! -d "$work/src/subprojects/$sub" ]; then
        echo "error: subprojects/$sub is missing; run Cartridge/Xemu/build-xemu.sh first" >&2
        exit 1
    fi
done

ports="$(awk -F'|' '$2 ~ /\.dylib/ {
    gsub(/ /, "", $2); gsub(/ /, "", $3); gsub(/ /, "", $5); gsub(/ /, "", $6)
    print $2, $3, $5, $6
}' "$sources")"
echo "$ports" | while read -r dylib package url sha; do
    if ! grep -qx "$package" "$installed"; then
        echo "error: $package is not in $installed; update macports/SOURCES.md" >&2
        exit 1
    fi
done
for product in "$xemu_dir"/Products/*.dylib; do
    lib="$(basename "$product")"
    [ "$lib" = "libxemu.dylib" ] && continue
    if ! echo "$ports" | grep -q "^$lib "; then
        echo "error: Products/$lib has no row in macports/SOURCES.md" >&2
        exit 1
    fi
done

if [ ! -d "$dsp56300/.git" ]; then
    git init --quiet "$dsp56300"
    git -C "$dsp56300" fetch --quiet --depth 1 "$dsp56300_url" "$dsp56300_commit"
fi

rm -rf "$staging"
mkdir -p "$staging/$name/xemu" "$staging/$name/fatx" "$staging/$name/dsp56300" "$staging/$name/macports" "$staging/$name/cartridge"

echo "==> xemu $xemu_commit"
git -C "$work/src" archive --format=tar "$xemu_commit" | tar -x -C "$staging/$name/xemu"
echo "==> subprojects"
for sub in $subprojects; do
    tar -c -C "$work/src" --exclude .git "subprojects/$sub" | tar -x -C "$staging/$name/xemu"
done
echo "==> fatx $fatx_commit"
git -C "$work/fatx" archive --format=tar "$fatx_commit" | tar -x -C "$staging/$name/fatx"

echo "==> dsp56300 $dsp56300_commit"
git -C "$dsp56300" archive --format=tar "$dsp56300_commit" | tar -x -C "$staging/$name/dsp56300"
mkdir -p "$staging/$name/dsp56300/.cargo"
(cd "$staging/$name/dsp56300" && cargo vendor --locked vendor > .cargo/config.toml)

echo "==> macports"
mkdir -p "$distfiles"
echo "$ports" | while read -r dylib package url sha; do
    port="${package%%=*}"
    file="$(basename "$url")"
    if [ ! -f "$distfiles/$file" ]; then
        curl -sfL --max-time 600 -o "$distfiles/$file.partial" "$url"
        mv "$distfiles/$file.partial" "$distfiles/$file"
    fi
    actual="$(shasum -a 256 "$distfiles/$file" | cut -d' ' -f1)"
    if [ "$actual" != "$sha" ] || ! grep -q "$sha" "$xemu_dir/macports/$port/Portfile"; then
        echo "error: $file is $actual; SOURCES.md and the $port Portfile expect $sha" >&2
        exit 1
    fi
    cp -R "$xemu_dir/macports/$port" "$staging/$name/macports/"
    cp "$distfiles/$file" "$staging/$name/macports/$port/"
    echo "$sha  $port/$file" >> "$staging/$name/macports/SHA256SUMS"
done
cp "$sources" "$staging/$name/macports/"

echo "==> Cartridge files"
for item in patches overlay include build-xemu.sh cartridge_xemu.exports README.md; do
    cp -R "$xemu_dir/$item" "$staging/$name/cartridge/"
done

tar -czf "$output" -C "$staging" "$name"
rm -rf "$staging"
shasum -a 256 "$output"
