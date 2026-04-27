#!/usr/bin/env bash
set -euo pipefail

# Usage: sudo ./scripts/inject.sh
# Mode is baked into the installed payload.dylib at install time (make install PAYLOAD=...).
# This script just attaches LLDB and dlopen()s the already-installed payload.
PAYLOAD="/Library/ScriptingAdditions/instantspaces.osax/Contents/Resources/payload.dylib"

PID="$(pgrep -x Dock || true)"
if [[ -z "${PID}" ]]; then
  echo "Dock not running? open /System/Library/CoreServices/Dock.app"
  exit 1
fi

# Attach, dlopen, detach. The payload __constructor__ patches on load.
# Check /private/var/tmp/instantspaces.${PID}.log for results.
/usr/bin/lldb -p "${PID}" -b \
  -o 'settings set target.process.thread.step-out-avoid-nodebug true' \
  -o "expr (void*)dlopen(\"$PAYLOAD\", 2)" \
  -o 'process detach' \
  -o 'quit'

echo "Injected into Dock pid=${PID}. Check /private/var/tmp/instantspaces.${PID}.log"
