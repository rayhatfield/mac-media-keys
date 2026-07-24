#!/bin/bash
# Smoke driver for MacMediaKeys — run from project root
set -e

APP=./build/DerivedData/Build/Products/Debug/MacMediaKeys.app
SCREENSHOT=${1:-/tmp/macmediakeys-smoke.png}

# 1. Build
echo "==> Building..."
xcodebuild -scheme MacMediaKeys -configuration Debug build \
  -derivedDataPath ./build/DerivedData \
  2>&1 | grep -E "BUILD SUCCEEDED|BUILD FAILED|error:"

# 2. Kill any running debug instance (leaves release instance alone)
if pgrep -f "DerivedData.*MacMediaKeys" > /dev/null 2>&1; then
  echo "==> Killing existing debug instance..."
  pkill -f "DerivedData.*MacMediaKeys" || true
  sleep 0.5
fi

# 3. Launch debug build
echo "==> Launching debug build..."
open "$APP"

# 4. Wait for menu bar item (up to 10s)
echo "==> Waiting for menu bar item..."
for i in $(seq 1 20); do
  if osascript -e 'tell application "System Events" to tell process "MacMediaKeys" to return count of menu bar items of menu bar 1' 2>/dev/null | grep -q "^[1-9]"; then
    break
  fi
  sleep 0.5
done

# 5. Verify: read menu items
echo "==> Checking menu items..."
osascript << 'OSASCRIPT'
tell application "System Events"
    tell process "MacMediaKeys"
        set mb1 to menu bar 1
        set mbi to menu bar item 1 of mb1
        set theMenu to menu 1 of mbi
        set menuItems to every menu item of theMenu
        set output to ""
        repeat with mi in menuItems
            try
                set output to output & (title of mi) & linefeed
            on error
                set output to output & "[separator]" & linefeed
            end try
        end repeat
        return output
    end tell
end tell
OSASCRIPT

# 6. Screenshot
echo "==> Taking screenshot..."
screencapture "$SCREENSHOT"
echo "Screenshot: $SCREENSHOT"

# 7. Quit debug instance
echo "==> Quitting debug instance..."
pkill -f "DerivedData.*MacMediaKeys" 2>/dev/null || true

echo "==> Done."
