#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-zero}"  # zero | min0125
PAYLOAD="/Library/ScriptingAdditions/instantspaces.osax/Contents/Resources/payload.dylib"

PID=$(pgrep -x Dock || true)
if [[ -z "${PID}" ]]; then
  echo "Dock not running? open /System/Library/CoreServices/Dock.app"
  exit 1
fi

/usr/bin/lldb -p "${PID}" -b \
  -o 'settings set target.process.thread.step-out-avoid-nodebug true' \
  -o "expr (int)setenv(\"INSTANTSPACES_MODE\",\"$MODE\",1)" \
  -o "expr (void*)dlopen(\"$PAYLOAD\", 2)" \
  -o 'expr (char*)dlerror()' \
  -o 'expr -- { void *(*my_dlsym)(void*, const char*) = (void*(*)(void*,const char*))dlsym; void *ps = my_dlsym((void*)-2,"instantspaces_patch"); (int)((ps)?((int(*)(void))ps)():-1); }' \
  -o 'expr -- { void *(*my_dlsym)(void*, const char*) = (void*(*)(void*,const char*))dlsym; void *vs = my_dlsym((void*)-2,"instantspaces_verify"); (int)((vs)?((int(*)(void))vs)():-1); }' \
  -o 'process detach' \
  -o 'quit'

echo "Injected payload into Dock (pid ${PID}) with mode=$MODE. Check Console.app (filter: instantspaces)."
