import Cocoa

/// Diagnostic logger. In DEBUG builds emits an `NSLog` and appends to
/// `/tmp/macmediakeys.log` (the unified-log filter doesn't always surface our
/// output reliably). Compiles to a no-op in Release.
func debugLog(_ message: String) {
    #if DEBUG
    let enabled = true
    #else
    let enabled = AppConfiguration.shared.isDebugLoggingEnabled()
    #endif
    guard enabled else { return }

    NSLog("MacMediaKeys: \(message)")
    let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
    if let data = line.data(using: .utf8) {
        let path = "/tmp/macmediakeys.log"
        if FileManager.default.fileExists(atPath: path),
           let handle = FileHandle(forWritingAtPath: path) {
            handle.seekToEndOfFile()
            handle.write(data)
            try? handle.close()
        } else {
            try? data.write(to: URL(fileURLWithPath: path))
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, MediaKeyTapDelegate, NowPlayingInterceptorDelegate {
    var statusItem: NSStatusItem?
    var mediaKeyTap: MediaKeyTap!
    var nowPlayingInterceptor: NowPlayingInterceptor!
    var currentController: MediaController!
    private let config = AppConfiguration.shared

    // Deduplication: multiple pathways may fire for the same keypress
    private var lastCommandTime: Date = .distantPast
    private var lastCommandKey: MediaKey?

    // Gating: remote-command-center events are only honored if the CGEvent tap
    // saw a real media-key event recently. Otherwise the system can trigger
    // playback via MPRemoteCommandCenter for reasons unrelated to the user
    // pressing a key — notably Bluetooth audio route changes.
    private var lastTapEventTime: Date = .distantPast
    private var cgEventTapActive: Bool = false
    private static let remoteCommandGraceWindow: TimeInterval = 0.5

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("MacMediaKeys: App launched")

        // Listen for configuration changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(configurationChanged),
            name: .appConfigurationChanged,
            object: nil
        )

        syncPresentationMode()

        // Load initial controller
        if let app = config.selectedApp() {
            currentController = MediaControllerFactory.controller(for: app)
            NSLog("MacMediaKeys: Initial target app: \(app.displayName)")
        }

        // Setup Now Playing interceptor to claim media key routing from rcd/mediaremoted
        nowPlayingInterceptor = NowPlayingInterceptor()
        nowPlayingInterceptor.delegate = self

        // Setup CGEvent media key tap (defer slightly to ensure UI is ready)
        DispatchQueue.main.async { [weak self] in
            self?.setupMediaKeyTap()
        }
    }

    func syncPresentationMode() {
        NSApp.setActivationPolicy(.accessory)
        destroyMainMenu()

        if config.showsMenuBarIcon() {
            setupStatusBarIfNeeded()
            rebuildMenu()
        } else {
            teardownStatusBar()
        }
    }

    private func setupStatusBarIfNeeded() {
        guard statusItem == nil else { return }

        NSLog("MacMediaKeys: Setting up status bar")

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem = item

        guard let button = item.button else {
            NSLog("MacMediaKeys: ERROR - Failed to get status item button")
            return
        }

        if let image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Media Keys") {
            image.isTemplate = true
            button.image = image
        } else {
            button.title = "♪"
        }

        NSLog("MacMediaKeys: Status item created, button: \(String(describing: button))")
    }

    private func teardownStatusBar() {
        guard let item = statusItem else { return }
        NSStatusBar.system.removeStatusItem(item)
        statusItem = nil
    }

    private func destroyMainMenu() {
        NSApp.mainMenu = nil
    }

    func rebuildMenu() {
        let menu = NSMenu()

        // Header
        let headerItem = NSMenuItem(title: "Forward media keys to:", action: nil, keyEquivalent: "")
        headerItem.isEnabled = false
        menu.addItem(headerItem)

        menu.addItem(NSMenuItem.separator())

        // App selection items - dynamically built from configuration
        let availableApps = config.allAvailableApps()
        let selectedBundleId = config.selectedAppBundleId()

        if availableApps.isEmpty {
            let emptyItem = NSMenuItem(title: "No apps configured", action: nil, keyEquivalent: "")
            emptyItem.isEnabled = false
            menu.addItem(emptyItem)
        } else {
            for app in availableApps {
                let item = NSMenuItem(
                    title: app.displayName,
                    action: #selector(selectApp(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = app
                item.state = (app.bundleIdentifier == selectedBundleId) ? .on : .off
                menu.addItem(item)
            }
        }

        menu.addItem(NSMenuItem.separator())

        // Settings
        let settingsItem = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // Status item
        let statusMenuItem = NSMenuItem(title: "Status: Initializing...", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        statusMenuItem.tag = 100
        menu.addItem(statusMenuItem)

        menu.addItem(NSMenuItem.separator())

        // Accessibility settings
        let accessibilityItem = NSMenuItem(
            title: "Open Accessibility Settings...",
            action: #selector(openAccessibilitySettings),
            keyEquivalent: ""
        )
        accessibilityItem.target = self
        menu.addItem(accessibilityItem)

        // Debug info
        let debugItem = NSMenuItem(
            title: "Copy Debug Info",
            action: #selector(copyDebugInfo(_:)),
            keyEquivalent: ""
        )
        debugItem.target = self
        menu.addItem(debugItem)

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu

        // Update status if we have it
        if MediaKeyTap.isAccessibilityEnabled() {
            updateStatus("Status: Active ✓")
        }
    }

    @objc func configurationChanged() {
        NSLog("MacMediaKeys: Configuration changed, rebuilding menu")
        syncPresentationMode()

        // Update controller if selected app changed or was removed
        if let app = config.selectedApp() {
            if currentController == nil || currentController.bundleIdentifier != app.bundleIdentifier {
                currentController = MediaControllerFactory.controller(for: app)
                NSLog("MacMediaKeys: Controller updated to: \(app.displayName)")
            }
        }
    }

    @objc func selectApp(_ sender: NSMenuItem) {
        guard let app = sender.representedObject as? CustomMediaApp else { return }

        // Update checkmarks
        if let menu = statusItem?.menu {
            for item in menu.items {
                if let itemApp = item.representedObject as? CustomMediaApp {
                    item.state = (itemApp.bundleIdentifier == app.bundleIdentifier) ? .on : .off
                }
            }
        }

        // Save and update controller
        config.setSelectedAppBundleId(app.bundleIdentifier)
        currentController = MediaControllerFactory.controller(for: app)
        NSLog("MacMediaKeys: Switched to: \(app.displayName)")
    }

    @objc func openSettings() {
        ConfigureAppsWindowController.show()
    }

    func setupMediaKeyTap() {
        mediaKeyTap = MediaKeyTap()
        mediaKeyTap.delegate = self

        if !MediaKeyTap.isAccessibilityEnabled() {
            _ = MediaKeyTap.checkAccessibilityPermission()
            updateStatus("Status: Need Accessibility Permission")
        }

        if mediaKeyTap.start() {
            cgEventTapActive = true
            updateStatus("Status: Active ✓")
        } else {
            cgEventTapActive = false
            updateStatus("Status: Need Accessibility Permission")
        }
    }

    func updateStatus(_ text: String) {
        if let menu = statusItem?.menu,
           let item = menu.item(withTag: 100) {
            item.title = text
        }
    }

    @objc func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func copyDebugInfo(_ sender: NSMenuItem) {
        let bundle  = Bundle.main
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build   = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let os      = ProcessInfo.processInfo.operatingSystemVersionString
        let selected = config.selectedApp().map { "\($0.displayName) (\($0.bundleIdentifier))" } ?? "None"
        let allApps  = config.allAvailableApps().map { $0.displayName }.joined(separator: ", ")
        let a11y    = MediaKeyTap.isAccessibilityEnabled()
        let logging = config.isDebugLoggingEnabled()

        var lines: [String] = [
            "## Media Key Forwarder — Debug Info",
            "",
            "**Version:** \(version) (build \(build))",
            "**macOS:** \(os)",
            "**Selected app:** \(selected)",
            "**Available apps:** \(allApps.isEmpty ? "None" : allApps)",
            "**Accessibility:** \(a11y ? "granted" : "not granted")",
            "**Event tap active:** \(cgEventTapActive ? "yes" : "no")",
            "**Debug logging:** \(logging ? "enabled" : "disabled")",
        ]

        let logPath = "/tmp/macmediakeys.log"
        if let log = try? String(contentsOfFile: logPath, encoding: .utf8), !log.isEmpty {
            let logLines = log.components(separatedBy: "\n")
            let trimmed  = logLines.suffix(200).joined(separator: "\n")
            lines += ["", "<details><summary>Log</summary>", "", "```", trimmed, "```", "", "</details>"]
        } else {
            lines += ["", "*(No log — enable Debug Logging in Settings, reproduce the issue, then copy again.)*"]
        }

        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)

        sender.title = "Copied!"
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            sender.title = "Copy Debug Info"
        }
    }

    @objc func quit() {
        NSApplication.shared.terminate(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !config.showsMenuBarIcon() {
            openSettings()
            return true
        }
        return false
    }

    // MARK: - Command Dispatch (shared by both pathways)

    /// Sends a media command to the current controller, with deduplication to avoid
    /// double-firing when both CGEvent tap and MPRemoteCommandCenter handle the same keypress.
    private func dispatchCommand(_ key: MediaKey, source: String) {
        let now = Date()
        if lastCommandKey == key, now.timeIntervalSince(lastCommandTime) < 0.3 {
            debugLog("dispatchCommand(\(key)) from \(source) DEDUPED")
            return
        }
        lastCommandKey = key
        lastCommandTime = now

        guard let controller = currentController else {
            NSLog("MacMediaKeys: No controller set")
            return
        }

        debugLog("dispatchCommand(\(key)) from \(source) → \(controller.displayName)")

        switch key {
        case .play:
            controller.playPause()
        case .next, .fast:
            controller.nextTrack()
        case .previous, .rewind:
            controller.previousTrack()
        }
    }

    // MARK: - MediaKeyTapDelegate

    func mediaKeyTap(_ tap: MediaKeyTap, receivedKey key: MediaKey) {
        lastTapEventTime = Date()
        dispatchCommand(key, source: "CGEventTap")
    }

    // MARK: - NowPlayingInterceptorDelegate

    func nowPlayingInterceptor(_ interceptor: NowPlayingInterceptor, receivedKey key: MediaKey) {
        // Require a recent CGEvent tap signal as proof that a hardware media key
        // was actually pressed. macOS issues MPRemoteCommandCenter callbacks for
        // things other than keypresses (e.g. Bluetooth audio route changes), and
        // without this gate those cause unexpected playback. If accessibility is
        // not granted the tap can't run, so fall back to ungated behavior.
        if cgEventTapActive,
           Date().timeIntervalSince(lastTapEventTime) > Self.remoteCommandGraceWindow {
            NSLog("MacMediaKeys: Ignoring remote command \(key) — no recent media-key event (likely audio route change)")
            return
        }
        dispatchCommand(key, source: "NowPlaying")
    }
}
