#!/usr/bin/env bash
# install-system.sh — privileged install of OSAX bundle + watcher binary
# Used by both `sudo make install` (direct) and the Homebrew formula (via pkgshare).
#
# Usage:
#   sudo bash install-system.sh              # installs min0125 (recommended)
#   sudo bash install-system.sh --mode zero  # installs zero mode
#   sudo bash install-system.sh --uninstall  # removes all system files
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MODE="min0125"
UNINSTALL=0

for arg in "$@"; do
  case "$arg" in
    --mode) shift; MODE="${1:-min0125}" ;;
    --mode=*) MODE="${arg#--mode=}" ;;
    --uninstall) UNINSTALL=1 ;;
  esac
done

OSAX_DIR="/Library/ScriptingAdditions/instantspaces.osax/Contents"
WATCHER_BIN="/usr/local/bin/instantspaces-watcher"
INJECT_BIN="/usr/local/bin/instantspaces-watcher-inject"

if [[ "$UNINSTALL" -eq 1 ]]; then
  echo "→ Removing OSAX bundle..."
  rm -rf /Library/ScriptingAdditions/instantspaces.osax
  echo "→ Removing watcher binaries..."
  rm -f "$WATCHER_BIN" "$INJECT_BIN"
  echo "✓ System files removed."
  exit 0
fi

# Resolve payload + watcher paths — works from both repo checkout and Homebrew pkgshare.
LIB_DIR="$SCRIPT_DIR"
# When invoked from Homebrew pkgshare, artefacts live in pkgshare/lib/.
if [[ -d "$SCRIPT_DIR/lib" ]]; then
  LIB_DIR="$SCRIPT_DIR/lib"
fi

PAYLOAD="$LIB_DIR/payload-${MODE}.dylib"
WATCHER_SRC="$LIB_DIR/watcher"
INFO_PLIST="$SCRIPT_DIR/../osax/Info.plist"
# When invoked from pkgshare, Info.plist lives in pkgshare/osax/.
if [[ -f "$SCRIPT_DIR/osax/Info.plist" ]]; then
  INFO_PLIST="$SCRIPT_DIR/osax/Info.plist"
fi
INJECT_SRC="$SCRIPT_DIR/../scripts/auto-inject.sh"
if [[ -f "$SCRIPT_DIR/../scripts/auto-inject.sh" ]]; then
  INJECT_SRC="$SCRIPT_DIR/../scripts/auto-inject.sh"
elif [[ -f "$SCRIPT_DIR/auto-inject.sh" ]]; then
  INJECT_SRC="$SCRIPT_DIR/auto-inject.sh"
fi

if [[ ! -f "$PAYLOAD" ]]; then
  echo "Error: payload not found at $PAYLOAD"
  echo "  Run 'make' in the repo first, or check the Homebrew install."
  exit 1
fi

echo "→ Installing OSAX bundle (mode: ${MODE})..."
mkdir -p "$OSAX_DIR/Resources"
cp "$INFO_PLIST" "$OSAX_DIR/Info.plist"
cp "$PAYLOAD"    "$OSAX_DIR/Resources/payload.dylib"
codesign -s - -f "$OSAX_DIR/Resources/payload.dylib" 2>/dev/null || true
xattr -dr com.apple.quarantine "$OSAX_DIR/Resources/payload.dylib" 2>/dev/null || true

echo "→ Installing watcher binary..."
cp "$WATCHER_SRC" "$WATCHER_BIN"
chmod +x "$WATCHER_BIN"
codesign -s - "$WATCHER_BIN" 2>/dev/null || true

echo "→ Installing inject script..."
cp "$INJECT_SRC" "$INJECT_BIN"
chmod +x "$INJECT_BIN"

echo "✓ Done. Mode: ${MODE}"
echo "  Next: bash install-agent.sh  (to set up the LaunchAgent)"
