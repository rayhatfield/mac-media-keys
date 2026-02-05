# Mac Media Keys Forwarder

A macOS menu bar app that forwards media keys (play/pause, next, previous) to a specific media application of your choice.

This is a modern replacement for [Mac Media Key Forwarder](https://github.com/milgra/macmediakeyforwarder), designed to work with macOS Sequoia (15.x) and later.

## Features

- Intercepts media keys and forwards them to your chosen app
- Supports multiple media players:
  - Spotify
  - Apple Music
  - VLC
  - Deezer
  - TIDAL
- Menu bar icon for easy access
- Remembers your selected app between launches

## Requirements

- macOS 13.0 (Ventura) or later
- Accessibility permission (required to intercept media keys)

## Building

```bash
./build.sh
```

This creates `build/MacMediaKeys.app`.

## Installation

1. Build the app using the command above
2. Copy to Applications: `cp -r build/MacMediaKeys.app /Applications/`
3. Open the app
4. Grant Accessibility permission when prompted:
   - Go to **System Settings > Privacy & Security > Accessibility**
   - Enable **MacMediaKeys**
5. Restart the app after granting permission

## Usage

1. Click the music note icon in the menu bar
2. Select your target media app from the list
3. Press media keys on your keyboard - they will be forwarded to the selected app

## How It Works

The app uses `CGEventTap` to intercept system-defined media key events before they reach other applications. When a media key is pressed, the app sends the corresponding command to your selected media player via AppleScript.

Key technical decisions for Sequoia compatibility:
- Uses `NSApplicationActivationPolicyAccessory` instead of `Prohibited` (background-only apps fail permission checks on Sequoia)
- Controls media apps via AppleScript rather than re-dispatching media key events

## License

MIT
