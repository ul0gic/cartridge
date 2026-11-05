#!/bin/sh
set -eu

if [ $# -ne 2 ]; then
    echo "usage: make-dmg.sh <Cartridge.app> <output.dmg>" >&2
    exit 64
fi

app="$1"
out="$2"
background="$(cd "$(dirname "$0")" && pwd)/dmg/background.tiff"
volume="Cartridge"
mount="/Volumes/$volume"

if [ -e "$mount" ]; then
    echo "error: $mount is already mounted; eject it first" >&2
    exit 1
fi
if [ -e "$out" ]; then
    echo "error: $out already exists" >&2
    exit 1
fi

work="$(mktemp -d)"
trap 'hdiutil detach "$mount" -quiet 2>/dev/null || true; rm -rf "$work"' EXIT

mkdir "$work/stage" "$work/stage/.background"
ditto "$app" "$work/stage/Cartridge.app"
ln -s /Applications "$work/stage/Applications"
cp "$background" "$work/stage/.background/background.tiff"
chflags hidden "$work/stage/.background"

hdiutil create -quiet -volname "$volume" -srcfolder "$work/stage" -fs HFS+ -format UDRW "$work/rw.dmg"
hdiutil attach -quiet -readwrite -noverify -noautoopen "$work/rw.dmg"

osascript <<'APPLESCRIPT'
tell application "Finder"
    tell disk "Cartridge"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set the bounds of container window to {200, 120, 860, 668}
        set viewOptions to the icon view options of container window
        set arrangement of viewOptions to not arranged
        set icon size of viewOptions to 128
        set text size of viewOptions to 13
        set background picture of viewOptions to file ".background:background.tiff"
        set extension hidden of item "Cartridge.app" to true
        set position of item "Cartridge.app" of container window to {180, 155}
        set position of item "Applications" of container window to {480, 155}
        set position of item ".background" of container window to {330, 330}
        close
        open
        update without registering applications
        delay 2
        close
    end tell
end tell
APPLESCRIPT

rm -rf "$mount/.fseventsd"
sync
hdiutil detach -quiet "$mount"
hdiutil convert -quiet "$work/rw.dmg" -format UDZO -imagekey zlib-level=9 -o "$out"
codesign --sign "Developer ID Application" --timestamp "$out"
