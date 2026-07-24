---
name: run-mac-media-keys
description: Run, build, launch, screenshot, start, test, verify, smoke test the MacMediaKeys macOS menu bar app
---

MacMediaKeys is a macOS menu bar app (Swift/Xcode, no main window) that forwards media keys to a chosen app. The driver is `.claude/skills/run-mac-media-keys/smoke.sh` — it builds, launches the debug binary, reads menu items via AppleScript, takes a screenshot, then quits the debug instance.

## Prerequisites

- Xcode + Developer ID signing (already set up in this repo — no extra steps)
- macOS 13+ (Ventura or later)
- No Homebrew packages needed

## Build

From project root:

```bash
xcodebuild -scheme MacMediaKeys -configuration Debug build \
  -derivedDataPath ./build/DerivedData 2>&1 | grep -E "BUILD SUCCEEDED|BUILD FAILED|error:"
```

Output: `./build/DerivedData/Build/Products/Debug/MacMediaKeys.app`  
Build time: ~7s warm (incremental). First cold build takes ~30s.

The iOSSimulator warning about CoreSimulator version is harmless — ignore it.

## Run (agent path)

```bash
bash .claude/skills/run-mac-media-keys/smoke.sh [/path/to/screenshot.png]
```

This script (verified 2026-07-01):
1. Builds with xcodebuild
2. Kills any existing debug instance
3. Launches `./build/DerivedData/Build/Products/Debug/MacMediaKeys.app`
4. Waits up to 10s for the menu bar item to appear
5. Reads all menu item titles via AppleScript (confirms the app is functional)
6. Takes a full-screen screenshot (default `/tmp/macmediakeys-smoke.png`)
7. Kills the debug instance with `pkill -f "DerivedData.*MacMediaKeys"`

### Interact via AppleScript

To open the menu and read items:

```bash
osascript << 'EOF'
tell application "System Events"
    tell process "MacMediaKeys"
        set mbi to menu bar item 1 of menu bar 1
        set theMenu to menu 1 of mbi
        repeat with mi in (every menu item of theMenu)
            try
                log title of mi
            end try
        end repeat
    end tell
end tell
EOF
```

To click a menu item (e.g., select Spotify):

```bash
osascript -e '
tell application "System Events"
    tell process "MacMediaKeys"
        click menu item "Spotify" of menu 1 of menu bar item 1 of menu bar 1
    end tell
end tell'
```

To take a screenshot:

```bash
screencapture /tmp/macmediakeys.png
```

Note: `screencapture -x` (no-shadow flag) exits 1 inside Claude Code's sandbox — use plain `screencapture`.

## Run (human path)

Install the release build to `/Applications/MacMediaKeys.app` and double-click, or:

```bash
open /Applications/MacMediaKeys.app
```

The app runs as an accessory (menu bar only — no Dock icon, not in Cmd+Tab). The ▶ icon appears in the right side of the menu bar. Click it to select which app gets media keys.

Quit via the app's menu → Quit, or `pkill MacMediaKeys`.

## Gotchas

- **Menu bar 1, not 2.** The app only has one menu bar (`menu bar 1`), unlike typical apps which have both a system menu bar and a menu bar for status items. Using `menu bar 2` gives "Invalid index".
- **`tell application "MacMediaKeys" to quit` hits the wrong instance** if both debug and release are running simultaneously. Use `pkill -f "DerivedData.*MacMediaKeys"` to target the debug build specifically.
- **Accessibility permission is NOT required to launch or read the menu.** Without it, the app shows "Status: Need Accessibility Permission" but still starts and displays the menu normally.
- **`NSApplicationActivationPolicyAccessory`** — the app never appears in the Dock or is focusable via Cmd+Tab, but it does appear as a process in System Events.
- **Debug log at `/tmp/macmediakeys.log`** — in Debug builds, all activity is logged there. Useful for tracing what the app does after a key event.

## Troubleshooting

| Symptom | Fix |
|---|---|
| `BUILD FAILED` with Swift compiler error | Run full build output: remove the `\| grep` filter |
| `Can't get menu bar 1 of process "MacMediaKeys"` | App hasn't finished launching — the smoke script waits up to 10s, but a slow machine may need more loops |
| `screencapture: cannot write file` | Parent directory doesn't exist — create it with `mkdir -p` first |
| Menu bar item missing after launch | Check if another MacMediaKeys instance already owns the status item slot; kill all with `pkill MacMediaKeys` and relaunch |
