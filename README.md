# instantspaces

Disable macOS Desktop Spaces switching animation by patching Dock **in-process** with a tiny scripting addition payload. Supports:
- macOS: 14 (Sonoma) and 15 (Sequoia)
- Arch: Apple Silicon (arm64e)
- Requires: SIP disabled, Xcode Command Line Tools

The whole patching mechanism is based on [yabai](https://github.com/koekeishiya/yabai)'s scripting addition. I just wanted to have it stand-alone to fix an issue with [redrawing of floating windows](https://github.com/koekeishiya/yabai/issues/2491).

<details>
<summary>How did I fix it?</summary>

The Spaces switching animation duration is being set to zero and probably fucks around with the compositor rendering phases, so that floating windows or popups are not being redrawn. Only way to fix this is triggering a redraw which is cumbersome

So I set a very small animation duration frame of 0.125 seconds that still allows for redraws but is faster than stock.

</details>


## Install

```sh
./scripts/install.sh
```

This builds an arm64e `payload.dylib`, installs it to:
```
/Library/ScriptingAdditions/instantspaces.osax/Contents/Resources/payload.dylib
```
and ad‑hoc signs it.

## Inject and verify

```sh
# Restart Dock so we patch early
killall Dock

# Inject and run patch + verify
sudo ./scripts/inject.sh
```

You should see messages in Console.app (filter: `instantspaces`) like:
```
[instantspaces] constructor: payload loaded into Dock pid=...
[instantspaces] Dock __TEXT=[0x... .. 0x... )
[instantspaces] Patched site @0x...: before=0x..., after=0x2f00e400
[instantspaces] Total sites patched: 2
[instantspaces] Verify: patched_count=2
[instantspaces] Verify patched @0x... => 0x2f00e400
...
```

Try switching Spaces (Ctrl+Arrow and/or trackpad swipe). It should now be instant on all paths.

## Uninstall

```sh
./scripts/uninstall.sh
```

## Notes

- This payload matches two known instruction patterns (Sonoma and Sequoia) and patches **all** matches within Dock’s `__TEXT` segment, then records and verifies patched addresses. On 14.7.5, two specific sites typically matter for Ctrl+Arrow and gesture switching; patching those removes animation.

- Logging:
  - Console.app: filter process “Dock” and term “instantspaces”
  - File: `/private/var/tmp/instantspaces.<DockPID>.log`

- If injection prints `dlopen ... incompatible architecture (have 'arm64', need 'arm64e')`, rebuild with:
  ```
  clang -arch arm64e ...
  ```

- If `dlopen` returns NULL, check `dlerror()` in the LLDB transcript. Fixes commonly include:
  - Move payload out of `~/Downloads` (quarantine)
  - `codesign -s - -f` the dylib
  - Ensure Developer Tools are permitted in System Settings

- If Ctrl+Arrow still animates:
  - Ensure “Displays have separate Spaces” is enabled (System Settings > Desktop & Dock)
  - Kill and restart Dock, then inject again
  - Confirm in LLDB: `image lookup -n instantspaces_verify` then call verify via dlsym (see script)

## Roadmap / TODO

- Optional non-zero minimal duration (e.g., 0.125s) via alternative opcode at patch site(s).