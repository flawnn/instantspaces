CC=clang
CFLAGS_COMMON=-mmacosx-version-min=14.0 -Wall -O2
FRAMEWORKS=-framework Cocoa
EXPORTS=-Wl,-exported_symbol,_instantspaces_patch -Wl,-exported_symbol,_instantspaces_verify

all: payload-zero.dylib payload-min0125.dylib watcher

payload-zero.dylib: src/payload.m
	$(CC) $(CFLAGS_COMMON) -arch arm64e -dynamiclib $(FRAMEWORKS) $(EXPORTS) src/payload.m -o $@

payload-min0125.dylib: src/payload.m
	$(CC) $(CFLAGS_COMMON) -DMODE_MIN0125 -arch arm64e -dynamiclib $(FRAMEWORKS) $(EXPORTS) src/payload.m -o $@

INJECT_MODE ?= min0125

watcher: src/watcher.c
	$(CC) $(CFLAGS_COMMON) -arch arm64e \
		-DINJECT_MODE='"$(INJECT_MODE)"' \
		src/watcher.c -o $@

PAYLOAD ?= payload-$(INJECT_MODE).dylib

install: $(PAYLOAD) osax/Info.plist
	sudo mkdir -p /Library/ScriptingAdditions/instantspaces.osax/Contents/Resources
	sudo cp osax/Info.plist /Library/ScriptingAdditions/instantspaces.osax/Contents/Info.plist
	sudo cp $(PAYLOAD) /Library/ScriptingAdditions/instantspaces.osax/Contents/Resources/payload.dylib
	sudo codesign -s - -f /Library/ScriptingAdditions/instantspaces.osax/Contents/Resources/payload.dylib || true
	sudo xattr -dr com.apple.quarantine /Library/ScriptingAdditions/instantspaces.osax/Contents/Resources/payload.dylib || true
# Install the watcher binary + LaunchAgent plist with correct paths substituted.
# Run after: make && sudo make install INJECT_MODE=min0125
install-agent: watcher
	sudo cp watcher /usr/local/bin/instantspaces-watcher
	sudo cp scripts/auto-inject.sh /usr/local/bin/instantspaces-watcher-inject
	sudo chmod +x /usr/local/bin/instantspaces-watcher-inject
	sudo codesign -s - /usr/local/bin/instantspaces-watcher || true
	mkdir -p $(HOME)/Library/LaunchAgents
	mkdir -p $(HOME)/Library/Logs
	sed -e 's|WATCHER_PATH|/usr/local/bin/instantspaces-watcher|g' \
	    -e 's|~/Library/Logs|$(HOME)/Library/Logs|g' \
		eu.flawn.instantspaces.inject.plist \
		> $(HOME)/Library/LaunchAgents/eu.flawn.instantspaces.inject.plist
	launchctl bootout gui/$(shell id -u)/eu.flawn.instantspaces.inject 2>/dev/null || true
	launchctl bootstrap gui/$(shell id -u) $(HOME)/Library/LaunchAgents/eu.flawn.instantspaces.inject.plist
	launchctl enable gui/$(shell id -u)/eu.flawn.instantspaces.inject
	@echo "LaunchAgent installed and loaded. Logs: $(HOME)/Library/Logs/instantspaces.watcher.*.log"

uninstall:
	launchctl bootout gui/$(shell id -u)/eu.flawn.instantspaces.inject 2>/dev/null || true
	rm -f ~/Library/LaunchAgents/eu.flawn.instantspaces.inject.plist
	sudo rm -f /usr/local/bin/instantspaces-watcher
	sudo rm -f /usr/local/bin/instantspaces-watcher-inject
	sudo rm -rf /Library/ScriptingAdditions/instantspaces.osax

clean:
	rm -f payload-zero.dylib payload-min0125.dylib watcher