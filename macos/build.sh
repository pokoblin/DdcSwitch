#!/bin/bash
# Builds DdcSwitch.app (Apple silicon) into ../dist and zips it for a release.
# The version comes from ../Cargo.toml so both platforms share it.
# Set SIGN_IDENTITY to a "Developer ID Application" identity to sign; the default is ad-hoc.
set -euo pipefail
cd "$(dirname "$0")"

VERSION=$(sed -n 's/^version = "\(.*\)"/\1/p' ../Cargo.toml | head -1)
DIST="$(cd .. && pwd)/dist"
APP="$DIST/DdcSwitch.app"
ARCHS=(--arch arm64)

echo "Building DdcSwitch $VERSION"
swift build -c release "${ARCHS[@]}" --product DdcSwitch
BIN="$(swift build -c release "${ARCHS[@]}" --show-bin-path)/DdcSwitch"
swift build -c release --product IconGen
ICONGEN="$(swift build -c release --show-bin-path)/IconGen"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DdcSwitch"
sed "s/@VERSION@/$VERSION/g" Info.plist > "$APP/Contents/Info.plist"

ICONSET="$(mktemp -d)/AppIcon.iconset"
"$ICONGEN" "$ICONSET"
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
rm -rf "$(dirname "$ICONSET")"

codesign --force --options runtime --timestamp=none --sign "${SIGN_IDENTITY:--}" "$APP"

ZIP="$DIST/DdcSwitch-$VERSION-macos.zip"
rm -f "$ZIP"
ditto -c -k --keepParent "$APP" "$ZIP"
echo "Built $APP"
echo "      $ZIP"
