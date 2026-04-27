#!/usr/bin/env bash
set -euo pipefail

# Config: choose your default mode (zero|min0125)
MODE="${1:-zero}"

PAYLOAD="/Library/ScriptingAdditions/instantspaces.osax/Contents/Resources/payload.dylib"

# Try injection a few times (works around occasional attach/transient hiccups)
tries=2
for attempt in $(seq 1 $tries); do
  # Wait for Dock to appear
  for i in {1..30}; do
    pgrep -x Dock >/dev/null && break
    sleep 1
  done

  # Give Dock 2s to initialise after appearing
  sleep 2

  PID=$(pgrep -x Dock)

  # Attach by PID and inject
  timeout 15 /usr/bin/lldb -p "$PID" -b \
    -o 'settings set target.process.thread.step-out-avoid-nodebug true' \
    -o "expr (void*)dlopen(\"$PAYLOAD\", 2)" \
    -o 'process detach' \
    -o 'quit' || true

  # After lldb detaches, poll log for confirmation
  LOG="/private/var/tmp/instantspaces.$(pgrep -x Dock).log"
  for i in {1..10}; do
    if [[ -f "$LOG" ]] && grep -q "Total sites patched: [1-9]" "$LOG"; then
      echo "patch confirmed"
      exit 0
    fi
    sleep 1
  done

  echo "patch not confirmed after 10s"
  sleep 2
done

echo "auto-inject failed after $tries attempts (mode=$MODE)"
exit 75  # temporary failure; launchd will retry per KeepAlive/ThrottleInterval
