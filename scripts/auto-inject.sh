#!/usr/bin/env bash
set -euo pipefail

# Config: choose your default mode (zero|min0125)
MODE="${1:-min0125}"

PAYLOAD="/Library/ScriptingAdditions/instantspaces.osax/Contents/Resources/payload.dylib"

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
  exit 0
fi

# Try injection a few times (works around occasional attach/transient hiccups)
tries=3
for attempt in $(seq 1 $tries); do
  echo "auto-inject attempt $attempt/$tries (mode=$MODE)"
  /usr/bin/lldb -p "${PID}" -b \
    -o 'settings set target.process.thread.step-out-avoid-no-debug true' \
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
exit 0