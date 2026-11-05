#!/bin/sh
set -eu

src="$SRCROOT/Xemu/Products"
dest="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Frameworks"

if ! ls "$src"/*.dylib >/dev/null 2>&1; then
    echo "error: no xemu libraries in $src; run Cartridge/Xemu/build-xemu.sh" >&2
    exit 1
fi

if [ "$CONFIGURATION" = "Release" ]; then
    timestamp="--timestamp"
else
    timestamp="--timestamp=none"
fi

rm -rf "$dest"
mkdir -p "$dest"
for library in "$src"/*.dylib; do
    cp -f "$library" "$dest/"
    codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --options runtime "$timestamp" "$dest/$(basename "$library")"
done

# Xcode skips the target's own CodeSign on incremental builds, so the bundle is resealed over Frameworks here.
codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --options runtime "$timestamp" \
    --entitlements "$SRCROOT/$CODE_SIGN_ENTITLEMENTS" "$TARGET_BUILD_DIR/$WRAPPER_NAME"
