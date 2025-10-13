#!/usr/bin/env bash
set -euo pipefail

# Config: choose your default mode (zero|min0125)
MODE="${1:-min0125}"

PAYLOAD="/Library/ScriptingAdditions/instantspaces.osax/Contents/Resources/payload.dylib"

# Set a custom process title so it is easy to find/kill via pgrep/pkill
if command -v exec -a >/dev/null 2>&1; then
  : # exec -a supported by bash builtin when used on invocation; noop here
fi

# Wait for Dock to appear
for i in {1..30}; do
  if pgrep -x Dock >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

PID="$(pgrep -x Dock || true)"
if [[ -z "${PID}" ]]; then
  echo "Dock not running; giving up."
  exit 75  # temporary failure so launchd can retry
fi

# Try injection a few times (works around occasional attach/transient hiccups)
tries=2
for attempt in $(seq 1 $tries); do
  echo "auto-inject attempt $attempt/$tries (mode=$MODE)"
  /usr/bin/lldb -p "${PID}" -b \
    -o 'settings set target.process.thread.step-out-avoid-nodebug true' \
    -o "expr (int)setenv(\"INSTANTSPACES_MODE\",\"$MODE\",1)" \
    -o "expr (void*)dlopen(\"$PAYLOAD\", 2)" \
    -o 'expr (char*)dlerror()' \
    -o 'expr -- { void *(*my_dlsym)(void*, const char*) = (void*(*)(void*,const char*))dlsym; void *ps = my_dlsym((void*)-2,"instantspaces_patch"); (int)((ps)?((int(*)(void))ps)():-1); }' \
    -o 'expr -- { void *(*my_dlsym)(void*, const char*) = (void*(*)(void*,const char*))dlsym; void *ps = my_dlsym((void*)-2,"instantspaces_patch"); (int)((ps)?((int(*)(void))ps)():-1); }' \
    -o 'expr -- { void *(*my_dlsym)(void*, const char*) = (void*(*)(void*,const char*))dlsym; void *vs = my_dlsym((void*)-2,"instantspaces_verify"); (int)((vs)?((int(*)(void))vs)():-1); }' \
    -o 'process detach' \
    -o 'quit' && {
      echo "auto-inject success"
      exit 0
    }
  sleep 2
done

echo "auto-inject failed after $tries attempts (mode=$MODE)"
exit 75  # temporary failure; launchd will retry per KeepAlive/ThrottleInterval
