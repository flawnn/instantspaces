#!/usr/bin/env bash
set -euo pipefail

# Usage: sudo ./scripts/inject.sh [zero|min0125]
MODE="${1:-min0125}"  # default to min0125 for stability with floaters
PAYLOAD="/Library/ScriptingAdditions/instantspaces.osax/Contents/Resources/payload.dylib"

PID="$(pgrep -x Dock || true)"
if [[ -z "${PID}" ]]; then
  echo "Dock not running? open /System/Library/CoreServices/Dock.app"
  exit 1
fi

# Attach, set mode, dlopen, patch TWICE, verify, detach.
# We do two patch passes to mitigate rare attach/timing hiccups.
# We also print dlerror() right after dlopen.
# Use compound expressions so LLDB doesn't lose temp vars between calls.
/usr/bin/lldb -p "${PID}" -b \
  -o 'settings set target.process.thread.step-out-avoid-nodebug true' \
  -o "expr (int)setenv(\"INSTANTSPACES_MODE\",\"$MODE\",1)" \
  -o "expr (void*)dlopen(\"$PAYLOAD\", 2)" \
  -o 'expr (char*)dlerror()' \
  -o 'expr -- { void *(*my_dlsym)(void*, const char*) = (void*(*)(void*,const char*))dlsym; void *ps = my_dlsym((void*)-2,"instantspaces_patch"); (int)((ps)?((int(*)(void))ps)():-1); }' \
  -o 'expr -- { void *(*my_dlsym)(void*, const char*) = (void*(*)(void*,const char*))dlsym; void *ps = my_dlsym((void*)-2,"instantspaces_patch"); (int)((ps)?((int(*)(void))ps)():-1); }' \
  -o 'expr -- { void *(*my_dlsym)(void*, const char*) = (void*(*)(void*,const char*))dlsym; void *vs = my_dlsym((void*)-2,"instantspaces_verify"); (int)((vs)?((int(*)(void))vs)():-1); }' \
  -o 'process detach' \
  -o 'quit'

echo "Injected payload into Dock (pid ${PID}) with mode=$MODE. See Console.app (filter: instantspaces) and /private/var/tmp/instantspaces.${PID}.log"
