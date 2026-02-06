# Mac Media Keys Forwarder

A macOS menu bar app that forwards media keys (play/pause, next, previous) to a specific media application of your choice.

This is a modern replacement for [Mac Media Key Forwarder](https://github.com/milgra/macmediakeyforwarder), designed to work with macOS Sequoia (15.x), Tahoe (26.x), and later.

## Features

- Intercepts media keys and forwards them to your chosen app
- Prevents Apple Music from hijacking your media keys
- Built-in support for Spotify and Apple Music
- Add any custom media app via "Configure Apps..."
- Menu bar icon for easy access
- Remembers your selected app between launches

## Download

Download the latest release from the [Releases page](https://github.com/rayhatfield/mac-media-keys/releases).

## Installation

1. Download `MacMediaKeys.zip` from the latest release
2. Unzip and drag `MacMediaKeys.app` to your Applications folder
3. **First launch**: Right-click the app and select "Open" (required for unsigned apps)
4. Grant Accessibility permission when prompted:
   - Click "Open System Settings" or go to **System Settings → Privacy & Security → Accessibility**
   - Enable **MacMediaKeys**
5. Restart the app after granting permission

> **Note**: Since this app is not notarized, macOS will warn you about it being from an "unidentified developer". This is normal for apps distributed outside the Mac App Store. Right-clicking and selecting "Open" bypasses this warning.

## Usage

1. Click the music note (♪) icon in the menu bar
2. Select your target media app from the list
3. Press media keys on your keyboard - they will be forwarded to the selected app

### Adding Custom Apps

1. Click the menu bar icon
2. Select "Configure Apps..."
3. Click "Add App..." and select any .app file
4. The app will now appear in your target list

## Requirements

- macOS 13.0 (Ventura) or later
- Accessibility permission (required to intercept media keys)

## Building from Source

```bash
# Clone the repository
git clone https://github.com/rayhatfield/mac-media-keys.git
cd mac-media-keys

# Build with Xcode
xcodebuild -scheme MacMediaKeys -configuration Release build

# The app will be in:
# ~/Library/Developer/Xcode/DerivedData/MacMediaKeys-*/Build/Products/Release/MacMediaKeys.app
```

## How It Works

The app uses `CGEventTap` to intercept system-defined media key events before they reach other applications. When a media key is pressed, the app sends the corresponding command to your selected media player via AppleScript (for supported apps) or direct keystroke injection (for other apps).

Key technical details:
- Intercepts both key-down AND key-up events to prevent `mediaremoted` from launching Apple Music
- Uses `NSApplicationActivationPolicyAccessory` for Sequoia/Tahoe compatibility
- Falls back to spacebar/arrow key injection for apps without AppleScript support

## Why Not on the Mac App Store?

This app requires Accessibility permissions to intercept and consume media key events. Mac App Store apps must be sandboxed, and sandboxed apps cannot request Accessibility permissions. This is why similar apps like [BeardedSpice](https://github.com/beardedspice/beardedspice) are also distributed outside the App Store.

## License

MIT
