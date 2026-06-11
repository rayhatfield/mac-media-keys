import Cocoa

// MARK: - Built-in Media Apps (Spotify and Apple Music only)

enum MediaApp: String, CaseIterable, Codable {
    case spotify = "Spotify"
    case appleMusic = "Apple Music"

    var bundleIdentifier: String {
        switch self {
        case .spotify: return "com.spotify.client"
        case .appleMusic: return "com.apple.Music"
        }
    }

    var displayName: String {
        return rawValue
    }

    // Convert to CustomMediaApp for unified handling
    func toCustomApp() -> CustomMediaApp {
        return CustomMediaApp(
            displayName: displayName,
            bundleIdentifier: bundleIdentifier,
            playPauseCommand: "playpause",
            nextTrackCommand: "next track",
            previousTrackCommand: "previous track"
        )
    }
}

// MARK: - Custom Media App (for user-added apps)

struct CustomMediaApp: Codable, Hashable, Identifiable {
    var id: String { bundleIdentifier }
    let displayName: String
    let bundleIdentifier: String
    var playPauseCommand: String = "playpause"
    var nextTrackCommand: String = "next track"
    var previousTrackCommand: String = "previous track"

    init(displayName: String, bundleIdentifier: String,
         playPauseCommand: String = "playpause",
         nextTrackCommand: String = "next track",
         previousTrackCommand: String = "previous track") {
        self.displayName = displayName
        self.bundleIdentifier = bundleIdentifier
        self.playPauseCommand = playPauseCommand
        self.nextTrackCommand = nextTrackCommand
        self.previousTrackCommand = previousTrackCommand
    }
}

// MARK: - Protocol for controlling media applications

protocol MediaController {
    var displayName: String { get }
    var bundleIdentifier: String { get }
    func playPause()
    func nextTrack()
    func previousTrack()
    func isRunning() -> Bool
}

// MARK: - Generic Media Controller (works with any app)

class GenericMediaController: MediaController {
    let displayName: String
    let bundleIdentifier: String
    private let playPauseCommand: String
    private let nextTrackCommand: String
    private let previousTrackCommand: String

    init(app: CustomMediaApp) {
        self.displayName = app.displayName
        self.bundleIdentifier = app.bundleIdentifier
        self.playPauseCommand = app.playPauseCommand
        self.nextTrackCommand = app.nextTrackCommand
        self.previousTrackCommand = app.previousTrackCommand
    }

    convenience init(builtInApp: MediaApp) {
        self.init(app: builtInApp.toCustomApp())
    }

    func playPause() {
        sendCommand(playPauseCommand)
    }

    func nextTrack() {
        sendCommand(nextTrackCommand)
    }

    func previousTrack() {
        sendCommand(previousTrackCommand)
    }

    func isRunning() -> Bool {
        let workspace = NSWorkspace.shared
        return workspace.runningApplications.contains { $0.bundleIdentifier == bundleIdentifier }
    }

    private func sendCommand(_ command: String) {
        // Launch the app if it's not running
        if !isRunning() {
            launchApp()
            // Wait a bit for the app to start, then send the command
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.executeAppleScript(command)
            }
            return
        }

        executeAppleScript(command)
    }

    private func launchApp() {
        let workspace = NSWorkspace.shared
        if let appURL = workspace.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            let configuration = NSWorkspace.OpenConfiguration()
            configuration.activates = false  // Don't bring to front
            workspace.openApplication(at: appURL, configuration: configuration) { [weak self] _, error in
                if let error = error {
                    NSLog("MediaController: Failed to launch \(self?.displayName ?? "app"): \(error)")
                } else {
                    NSLog("MediaController: Launched \(self?.displayName ?? "app")")
                }
            }
        } else {
            NSLog("MediaController: Could not find application \(displayName)")
        }
    }

    private func executeAppleScript(_ command: String) {
        let script = "tell application \"\(displayName)\" to \(command)"
        debugLog("AppleScript: \(script)")

        guard let appleScript = NSAppleScript(source: script) else {
            debugLog("AppleScript: failed to create script object")
            return
        }

        var errorDict: NSDictionary?
        appleScript.executeAndReturnError(&errorDict)

        if let error = errorDict {
            let code = error[NSAppleScript.errorNumber] as? Int ?? -1
            let msg  = error[NSAppleScript.errorMessage] as? String ?? "unknown"
            debugLog("AppleScript: failed (code \(code)): \(msg)")
            if code == -1743 {
                // Automation permission not granted. Signal AppDelegate to activate the
                // app and retry — macOS will surface the TCC prompt when we're in foreground.
                debugLog("AppleScript: requesting Automation permission for \(displayName)")
                NotificationCenter.default.post(
                    name: .automationPermissionRequired,
                    object: nil,
                    userInfo: ["displayName": displayName, "bundleIdentifier": bundleIdentifier, "command": command]
                )
            } else {
                debugLog("AppleScript: falling back to keystroke")
                sendKeystrokeToApp(command)
            }
        } else {
            debugLog("AppleScript: succeeded")
        }
    }

    private func sendKeystrokeToApp(_ command: String) {
        // For apps that don't support AppleScript media commands,
        // send a keystroke directly to the app's process via postToPid —
        // no activation required, so the user's current window keeps focus.
        debugLog("Keystroke: falling back for \(displayName) command=\(command)")

        let keyCode: CGKeyCode
        if command.contains("play") || command.contains("pause") {
            keyCode = 49  // spacebar
        } else if command.contains("next") {
            keyCode = 124  // right arrow
        } else if command.contains("previous") {
            keyCode = 123  // left arrow
        } else {
            debugLog("Keystroke: unknown command '\(command)'")
            return
        }

        guard let app = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == bundleIdentifier
        }) else {
            debugLog("Keystroke: \(displayName) not found in running apps")
            return
        }

        let pid = app.processIdentifier
        debugLog("Keystroke: sending keyCode=\(keyCode) to \(displayName) pid=\(pid) active=\(app.isActive)")

        guard let source = CGEventSource(stateID: .hidSystemState) else {
            NSLog("MediaController: Failed to create event source")
            return
        }

        // Some apps (e.g. Deezer) require modifier keys for next/previous
        let needsShift = (command.contains("next") || command.contains("previous"))
            && bundleIdentifier == "com.deezer.deezer-desktop"

        // Electron/Chromium apps drop modifier+key events sent via postToPid when
        // in the background. Briefly activate the app, post to the session tap
        // (which now targets the focused app), then restore focus.
        if needsShift && !app.isActive {
            let previous = NSWorkspace.shared.frontmostApplication
            app.activate(options: [.activateIgnoringOtherApps])
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
                    keyDown.flags = .maskShift
                    keyDown.post(tap: .cgSessionEventTap)
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
                        keyUp.flags = .maskShift
                        keyUp.post(tap: .cgSessionEventTap)
                    }
                    previous?.activate(options: [.activateIgnoringOtherApps])
                    debugLog("Keystroke: sent to \(self.displayName) via focus swap")
                }
            }
            return
        }

        if let keyDown = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true) {
            if needsShift { keyDown.flags = .maskShift }
            keyDown.postToPid(pid)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            if let keyUp = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false) {
                if needsShift { keyUp.flags = .maskShift }
                keyUp.postToPid(pid)
            }
            debugLog("Keystroke: sent to \(self.displayName) via postToPid")
        }
    }
}

// MARK: - Factory to create controllers

class MediaControllerFactory {
    static func controller(for builtInApp: MediaApp) -> MediaController {
        return GenericMediaController(builtInApp: builtInApp)
    }

    static func controller(for customApp: CustomMediaApp) -> MediaController {
        return GenericMediaController(app: customApp)
    }
}
