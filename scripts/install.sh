#!/usr/bin/env bash
set -euo pipefail

make
sudo mkdir -p /Library/ScriptingAdditions/instantspaces.osax/Contents/Resources
sudo cp osax/Info.plist /Library/ScriptingAdditions/instantspaces.osax/Contents/Info.plist
sudo cp payload.dylib /Library/ScriptingAdditions/instantspaces.osax/Contents/Resources/payload.dylib
sudo codesign -s - -f /Library/ScriptingAdditions/instantspaces.osax/Contents/Resources/payload.dylib || true
sudo xattr -dr com.apple.quarantine /Library/ScriptingAdditions/instantspaces.osax/Contents/Resources/payload.dylib || true
echo "Installed to /Library/ScriptingAdditions/instantspaces.osax"