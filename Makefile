CC=clang
CFLAGS_COMMON=-mmacosx-version-min=14.0 -Wall -O2
FRAMEWORKS=-framework Cocoa
EXPORTS=-Wl,-exported_symbol,_instantspaces_patch -Wl,-exported_symbol,_instantspaces_verify

all: payload.dylib

payload.dylib: src/payload.m
	$(CC) $(CFLAGS_COMMON) -arch arm64e -dynamiclib $(FRAMEWORKS) $(EXPORTS) src/payload.m -o $@

install: payload.dylib osax/Info.plist
	sudo mkdir -p /Library/ScriptingAdditions/instantspaces.osax/Contents/Resources
	sudo cp osax/Info.plist /Library/ScriptingAdditions/instantspaces.osax/Contents/Info.plist
	sudo cp payload.dylib /Library/ScriptingAdditions/instantspaces.osax/Contents/Resources/payload.dylib
	sudo codesign -s - -f /Library/ScriptingAdditions/instantspaces.osax/Contents/Resources/payload.dylib || true
	sudo xattr -dr com.apple.quarantine /Library/ScriptingAdditions/instantspaces.osax/Contents/Resources/payload.dylib || true

uninstall:
	sudo rm -rf /Library/ScriptingAdditions/instantspaces.osax

clean:
	rm -f payload.dylib