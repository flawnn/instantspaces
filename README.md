# instantspaces

Disable macOS Desktop Spaces switching animation by patching Dock **in-process** with a tiny scripting addition payload.

- **macOS:** 14 (Sonoma), 15 (Sequoia), 26 (Tahoe)
- **Arch:** Apple Silicon (`arm64e`)  
- **Modes:** `zero`, `min0125`  
- **Requires:** SIP disabled, Xcode Command Line Tools

The whole patching mechanism is based on [yabai](https://github.com/koekeishiya/yabai)'s scripting addition. I just wanted to have it stand-alone to fix an issue with [redrawing of floating windows](https://github.com/koekeishiya/yabai/issues/2491).

<details>
<summary>How did you fix this mysterious issue? 🤔</summary>
<br>

> The Spaces switching animation duration is being set to zero and probably fucks around with the compositor rendering phases, so that floating windows or popups are not being redrawn. Only way to fix this is triggering a redraw which is cumbersome.
>
> I played around with the animation duration frames, and set a very small animation duration frame of 0.125 seconds that still allows for redraws but is faster than stock. Profit!

</details>

## Install via Homebrew (recommended)

```sh
brew tap flawnn/homebrew
brew install --HEAD flawnn/homebrew/instantspaces
```

After install, Homebrew will print setup instructions. In short:

```sh
# 1. Install system files — choose your mode (default: min0125)
sudo bash $(brew --prefix)/share/instantspaces/install-system.sh

# For zero mode instead:
sudo bash $(brew --prefix)/share/instantspaces/install-system.sh --mode zero

# 2. Install the watcher LaunchAgent (auto-injects at login)
bash $(brew --prefix)/share/instantspaces/install-agent.sh
```

> Not sure which mode to pick? See [Modes](#modes) below.

---

## Build and install (manual)

Choose a mode at install time — mode is baked into the binary, not set at runtime:

```sh
# Build both dylibs
make

# Install min0125 mode (0.125s — recommended, fixes floating window redraws)
sudo bash scripts/install-system.sh

# Install zero mode (instant, may cause floating window flicker)
sudo bash scripts/install-system.sh --mode zero
```

## Inject and patch

```sh
# Restart Dock so we patch early, then inject
killall Dock
sudo ./scripts/inject.sh

# Or use the auto-inject script (handles Dock wait + confirmation)
sudo ./scripts/auto-inject.sh min0125
```

### What the injector does
- `dlopen()`s the installed payload
- The `__constructor__` fires immediately on load and patches all sites
- Confirm via log: `grep "Total sites patched" /private/var/tmp/instantspaces.*.log`

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
Modes are baked into the installed dylib at `make install` time. To switch:
```sh
sudo make install PAYLOAD=payload-zero.dylib
killall Dock && sudo ./scripts/inject.sh
```

---

## Auto-run at login (LaunchAgent + watcher)

`make install-agent` installs a persistent watcher daemon that:
- Injects automatically at login
- Re-injects automatically whenever Dock restarts

```sh
# Build everything and install the dylib first
make
sudo bash scripts/install-system.sh        # min0125 (default)
# sudo bash scripts/install-system.sh --mode zero  # for zero mode

# Then install the watcher and LaunchAgent
bash scripts/install-agent.sh
```

The watcher runs as a per-user LaunchAgent. Logs appear in `~/Library/Logs/instantspaces.watcher.*.log`.

To unload/uninstall everything:
```sh
make uninstall
```

> [!NOTE]
> On first use, macOS may prompt to allow Terminal/LLDB under Privacy & Security → Developer Tools. Run `sudo ./scripts/inject.sh` once manually if the prompt does not appear automatically.

---

## Uninstall

```sh
bash scripts/install-agent.sh --uninstall
sudo bash scripts/install-system.sh --uninstall
```

---

## Troubleshooting

Feel free to open a GitHub Issue!
