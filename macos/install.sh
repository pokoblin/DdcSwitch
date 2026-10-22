#!/bin/bash
# Builds DdcSwitch, installs it to /Applications (or ~/Applications) and starts it.
set -euo pipefail
cd "$(dirname "$0")"

./build.sh

DEST=/Applications
[ -w "$DEST" ] || DEST="$HOME/Applications"
mkdir -p "$DEST"

# Let a running copy quit cleanly before replacing it.
if [ -x "$DEST/DdcSwitch.app/Contents/MacOS/DdcSwitch" ]; then
    "$DEST/DdcSwitch.app/Contents/MacOS/DdcSwitch" --quit || true
fi

rm -rf "$DEST/DdcSwitch.app"
ditto ../dist/DdcSwitch.app "$DEST/DdcSwitch.app"
open "$DEST/DdcSwitch.app"
echo "Installed to $DEST/DdcSwitch.app and started"
