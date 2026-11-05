#!/bin/sh
set -eu

src="$SRCROOT/Cores"
dest="$TARGET_BUILD_DIR/$CONTENTS_FOLDER_PATH/Frameworks/Cores"

if ! ls "$src"/*.dylib >/dev/null 2>&1; then
    echo "error: no cores in $src; run Cartridge/Scripts/fetch-cores.py" >&2
    exit 1
fi

if [ "$CONFIGURATION" = "Release" ]; then
    timestamp="--timestamp"
else
    timestamp="--timestamp=none"
fi

rm -rf "$dest"
mkdir -p "$dest"
for core in "$src"/*.dylib; do
    cp -f "$core" "$dest/"
    codesign --force --sign "$EXPANDED_CODE_SIGN_IDENTITY" --options runtime "$timestamp" "$dest/$(basename "$core")"
done
