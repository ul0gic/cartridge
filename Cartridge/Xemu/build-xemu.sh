#!/bin/sh
set -eu

xemu_url="https://github.com/xemu-project/xemu.git"
xemu_tag="v0.8.139"
xemu_commit="aa54c34cae1c09410d74c69a44210a9867fe2d16"
fatx_url="https://github.com/XboxDev/fatx.git"
fatx_commit="4fd8e81324d67f734dbfd3606f78f6981ff30d51"
arch="arm64"
# build.sh:204-205 sets this minimum for arm64.
macos_min_ver="14.0"

xemu_dir="$(cd "$(dirname "$0")" && pwd)"
root="$(cd "$xemu_dir/../.." && pwd)"
work="$root/.build/xemu"
src="$work/src"
fatx="$work/fatx"
build="$work/build"
products="$xemu_dir/Products"
tools="$root/.build/xemu-tools"
python="${PYTHON:-python3}"

step() {
    echo "==> $*"
}

apply_patches() {
    tree="$1"
    shift
    for patch in "$@"; do
        [ -e "$patch" ] || continue
        echo "git apply --check $(basename "$patch")"
        git -C "$tree" apply --check "$patch"
        git -C "$tree" apply "$patch"
    done
}

bundle() {
    binary="$1"
    dest="$2"
    name="$3"
    queue="$work/bundle.queue"

    rm -rf "$dest"
    mkdir -p "$dest"
    cp "$binary" "$dest/$name"
    chmod u+w "$dest/$name"
    if [ -n "$(otool -D "$dest/$name" | tail -n +2)" ]; then
        install_name_tool -id "@loader_path/$name" "$dest/$name"
    fi
    printf '%s\n' "$dest/$name" > "$queue"

    while [ -s "$queue" ]; do
        file="$(head -n 1 "$queue")"
        sed -i '' 1d "$queue"
        unexpected="$(otool -L "$file" | tail -n +2 | awk '{print $1}' |
            grep -v -e '^/usr/lib/' -e '^/System/' -e '^/opt/local/' -e '^@loader_path/' || true)"
        if [ -n "$unexpected" ]; then
            echo "error: $file links outside the system and MacPorts: $unexpected" >&2
            exit 1
        fi
        for dep in $(otool -L "$file" | tail -n +2 | awk '{print $1}' | grep '^/opt/local/' || true); do
            base="$(basename "$dep")"
            if [ ! -e "$dest/$base" ]; then
                cp -L "$lib_prefix/lib/$base" "$dest/$base"
                chmod u+w "$dest/$base"
                install_name_tool -id "@loader_path/$base" "$dest/$base"
                printf '%s\n' "$dest/$base" >> "$queue"
            fi
            install_name_tool -change "$dep" "@loader_path/$base" "$file"
        done
    done
    rm -f "$queue"

    # build.sh:55 re-signs ad hoc after install_name_tool; arm64 refuses unsigned code.
    for file in "$dest"/*; do
        codesign --force --sign - "$file"
    done
}

mkdir -p "$work"

step "xemu $xemu_tag"
if [ ! -d "$src/.git" ]; then
    git clone --quiet --depth 1 --branch "$xemu_tag" "$xemu_url" "$src"
fi
tagged="$(git -C "$src" rev-parse "$xemu_tag^{commit}")"
if [ "$tagged" != "$xemu_commit" ]; then
    echo "error: $xemu_tag is $tagged, expected $xemu_commit" >&2
    exit 1
fi
git -C "$src" reset --quiet --hard
git -C "$src" checkout --quiet --detach "$xemu_commit"
git -C "$src" clean -fdq

step "fatx $fatx_commit"
if [ ! -d "$fatx/.git" ]; then
    git init --quiet "$fatx"
    git -C "$fatx" fetch --quiet --depth 1 "$fatx_url" "$fatx_commit"
fi
git -C "$fatx" reset --quiet --hard
git -C "$fatx" checkout --quiet --detach "$fatx_commit"
git -C "$fatx" clean -fdq

step "patches"
apply_patches "$fatx" "$xemu_dir"/patches/fatx/*.patch
apply_patches "$src" "$xemu_dir"/patches/*.patch

step "overlay"
cp -R "$xemu_dir/overlay/." "$src/"
cp "$xemu_dir/include/cartridge_xemu.h" "$src/ui/cartridge/"
cp "$xemu_dir/cartridge_xemu.exports" "$src/ui/cartridge/"
mkdir -p "$src/ui/cartridge/libfatx"
cp "$fatx"/libfatx/*.c "$fatx"/libfatx/*.h "$src/ui/cartridge/libfatx/"

step "macOS libraries ($arch)"
(cd "$work" && "$python" "$src/scripts/download-macos-libs.py" "$arch")
lib_prefix="$work/macos-libs/$arch/opt/local"

step "SDK"
sdk="$(xcrun --sdk macosx --show-sdk-path)"
export SDKROOT="$sdk"
echo "$sdk"

step "configure"
mkdir -p "$build"
cflags="-arch $arch -target $arch-apple-macos$macos_min_ver -isysroot $sdk -I$lib_prefix/include -mmacosx-version-min=$macos_min_ver"
(
    cd "$build"
    CFLAGS="$cflags" \
        LDFLAGS="-arch $arch -isysroot $sdk" \
        PKG_CONFIG_LIBDIR="$lib_prefix/lib/pkgconfig" \
        "$src/configure" \
        --python="$(command -v "$python")" \
        --extra-cflags="-DXBOX=1 $cflags" \
        --extra-ldflags="-headerpad_max_install_names" \
        --target-list=i386-softmmu \
        --disable-cocoa \
        --cross-prefix= \
        --enable-shared-lib \
        --enable-tools
)

step "build libqemu-i386-softmmu.dylib and qemu-img"
ninja -C "$build" -j "$(sysctl -n hw.logicalcpu)" libqemu-i386-softmmu.dylib qemu-img

step "Products"
bundle "$build/libqemu-i386-softmmu.dylib" "$products" libxemu.dylib

step "verification tools"
bundle "$build/qemu-img" "$tools" qemu-img

step "done"
lipo -archs "$products/libxemu.dylib"
otool -L "$products"/*.dylib | grep -c /opt/local || true
nm -gU "$products/libxemu.dylib"
