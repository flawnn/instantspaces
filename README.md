# instantspaces

Disable macOS Desktop Spaces switching animation by patching Dock **in-process** with a tiny scripting addition payload.

| | |
|---|---|
| **macOS** | 14 (Sonoma), 15 (Sequoia) |
| **Arch** | Apple Silicon (`arm64e`) |
| **Modes** | `zero`, `min0125` |
| **Requires** | SIP disabled, Xcode Command Line Tools |

The whole patching mechanism is based on [yabai](https://github.com/koekeishiya/yabai)'s scripting addition. I just wanted to have it stand-alone to fix an issue with [redrawing of floating windows](https://github.com/koekeishiya/yabai/issues/2491).

<details>
<summary>⁉️ How did I fix it?</summary>
<br>

> The Spaces switching animation duration is being set to zero and probably fucks around with the compositor rendering phases, so that floating windows or popups are not being redrawn. Only way to fix this is triggering a redraw which is cumbersome
>
> So I set a very small animation duration frame of 0.125 seconds that still allows for redraws but is faster than stock.

</details>

## Inject and patch

> [!TIP]
> Restart Dock first, then inject and patch twice — the script already does two patch passes followed by verify. Patching twice works around rare attach or timing hiccups.

```sh
# Restart Dock so we patch early
killall Dock

# Inject and patch with a mode:
#   zero    -> 0.0s animation (instant)
#   min0125 -> 0.125s animation (near-instant; helps floating windows)
sudo ./scripts/inject.sh min0125
# or
sudo ./scripts/inject.sh zero
```

### What the injector does
- Sets `INSTANTSPACES_MODE` inside the Dock process
- `dlopen()`s the payload
- Calls `instantspaces_patch()` twice in a row
- Calls `instantspaces_verify()` to list/confirm patched sites

### Check logs
- Console.app: filter `"Dock"` and `"[instantspaces]"`
- File log: `/private/var/tmp/instantspaces.<DockPID>.log`

You'll see messages like:
```
[instantspaces] constructor: payload loaded into Dock pid=...
[instantspaces] instantspaces_patch: entered (mode=min0125)
[instantspaces] Dock __TEXT=[0x... .. 0x... )
[instantspaces] Patched site @0x...: before=0x..., after=0x1e681000
[instantspaces] Total sites patched: 2
[instantspaces] Verify: patched_count=2
[instantspaces] Verify patched @0x... => 0x1e681000
```

---

## Modes

| Mode | Opcode | Effect |
|------|--------|--------|
| `zero` | `0x2f00e400` | Forces duration to 0.0s — instant, but can cause floating windows to momentarily disappear |
| `min0125` | `0x1e681000` (`fmov d0, #0.125`) | Forces 0.125s — near-instant while giving the compositor a frame to redraw |

### Switching modes
Modes are set per injection. To change, restart Dock and re-run with the desired mode:
```sh
killall Dock; sudo ./scripts/inject.sh min0125
```

---

## Auto-run at login (LaunchAgent)

To inject automatically on login (and after Dock relaunches), install a per-user LaunchAgent that runs a small retrying injector wrapper.

1. Edit `scripts/auto-inject.sh` to choose your default mode (`zero` or `min0125`). It already retries multiple times.
2. Copy and adjust the LaunchAgent — in `eu.flawn.instantspaces.inject.plist`, set the `ProgramArguments` path to your `auto-inject.sh`.
3. Install and load:

```sh
# Create ~/Library/LaunchAgents if needed
mkdir -p ~/Library/LaunchAgents

# Copy the plist
cp eu.flawn.instantspaces.inject.plist ~/Library/LaunchAgents/

# Load (for the current user session)
launchctl bootstrap gui/$UID ~/Library/LaunchAgents/eu.flawn.instantspaces.inject.plist
launchctl enable gui/$UID/eu.flawn.instantspaces.inject
launchctl kickstart -k gui/$UID/eu.flawn.instantspaces.inject
```

To unload/disable:
```sh
launchctl bootout gui/$UID ~/Library/LaunchAgents/eu.flawn.instantspaces.inject.plist
launchctl disable gui/$UID/eu.flawn.instantspaces.inject
```

> [!NOTE]
> The agent runs in your user session (Dock is per-user). It will attempt injection repeatedly for a short window after login and also if Dock restarts.
> On first use, macOS may prompt to allow Terminal/LLDB under Privacy & Security → Developer Tools. Run the injector once manually if prompts do not appear in background.

---

## Uninstall

```sh
# Optional: unload agent if installed
launchctl bootout gui/$UID ~/Library/LaunchAgents/eu.flawn.instantspaces.inject.plist 2>/dev/null || true
rm -f ~/Library/LaunchAgents/eu.flawn.instantspaces.inject.plist

# Remove the osax payload
./scripts/uninstall.sh
```

---

## Troubleshooting

**`dlopen` returns `NULL`**
- Ensure the payload is `arm64e` (the `Makefile` builds `arm64e`)
- Clear quarantine and ad-hoc sign (`install.sh` and `make install` do this)
- Run once manually to grant Developer Tools permission (Terminal/LLDB)

**`EXC_BREAKPOINT` during LLDB expr**
- Retry inject — the script patches twice by default to withstand occasional attach hiccups
- Ensure SIP is relaxed consistently, and "Displays have separate Spaces" is enabled in System Settings → Desktop & Dock

**Animation still present**
- Use `min0125` mode for stability if floaters disappear on `zero`
- Confirm Console shows `"Total sites patched: 2"` (or more) and Verify entries
- Kill Dock and inject again to patch earlier in its lifecycle
