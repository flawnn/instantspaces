#!/usr/bin/env bash
# install-agent.sh — install (or uninstall) the watcher LaunchAgent
# Used by both `make install-agent` (direct) and the Homebrew formula (via pkgshare).
#
# Usage:
#   bash install-agent.sh            # install + load LaunchAgent
#   bash install-agent.sh --uninstall
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
UNINSTALL=0

for arg in "$@"; do
  case "$arg" in
    --uninstall) UNINSTALL=1 ;;
  esac
done

LABEL="eu.flawn.instantspaces.inject"
PLIST_DEST="$HOME/Library/LaunchAgents/${LABEL}.plist"
WATCHER_BIN="/usr/local/bin/instantspaces-watcher"

# Resolve plist template — works from repo root or Homebrew pkgshare.
PLIST_SRC="$SCRIPT_DIR/../eu.flawn.instantspaces.inject.plist"
if [[ -f "$SCRIPT_DIR/${LABEL}.plist" ]]; then
  PLIST_SRC="$SCRIPT_DIR/${LABEL}.plist"
fi

if [[ "$UNINSTALL" -eq 1 ]]; then
  echo "→ Unloading LaunchAgent..."
  launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true
  rm -f "$PLIST_DEST"
  echo "✓ LaunchAgent removed."
  exit 0
fi

if [[ ! -f "$WATCHER_BIN" ]]; then
  echo "Error: watcher binary not found at $WATCHER_BIN"
  echo "  Run 'sudo bash install-system.sh' first."
  exit 1
fi

echo "→ Installing LaunchAgent..."
mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
sed -e "s|WATCHER_PATH|${WATCHER_BIN}|g" \
    -e "s|~/Library/Logs|${HOME}/Library/Logs|g" \
    "$PLIST_SRC" > "$PLIST_DEST"

launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST_DEST"
launchctl enable "gui/$(id -u)/${LABEL}"

echo "✓ LaunchAgent installed and loaded."
echo "  Logs: $HOME/Library/Logs/instantspaces.watcher.{out,err}.log"
