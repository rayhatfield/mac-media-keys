import Cocoa

/// Diagnostic logger. In DEBUG builds emits an `NSLog` and appends to
/// `/tmp/macmediakeys.log` (the unified-log filter doesn't always surface our
/// output reliably). Compiles to a no-op in Release.
func debugLog(_ message: String) {
#if DEBUG
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
#endif
}

class AppDelegate: NSObject, NSApplicationDelegate, MediaKeyTapDelegate, NowPlayingInterceptorDelegate {
    var statusItem: NSStatusItem!
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

        // Setup status bar first
        setupStatusBar()

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

    func setupStatusBar() {
        NSLog("MacMediaKeys: Setting up status bar")

        // Create the status item with square length (compact)
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        guard let button = statusItem.button else {
            NSLog("MacMediaKeys: ERROR - Failed to get status item button")
            return
        }

        // Use SF Symbol matching the app icon
        if let image = NSImage(systemSymbolName: "play.fill", accessibilityDescription: "Media Keys") {
            image.isTemplate = true  // Adapts to light/dark mode
            button.image = image
        } else {
            // Fallback to compact text
            button.title = "♪"
        }

        NSLog("MacMediaKeys: Status item created, button: \(String(describing: button))")

        rebuildMenu()

        NSLog("MacMediaKeys: Status bar setup complete")
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

        // Configure Apps
        let configureItem = NSMenuItem(
            title: "Configure Apps...",
            action: #selector(openConfigureApps),
            keyEquivalent: ","
        )
        configureItem.target = self
        menu.addItem(configureItem)

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

        menu.addItem(NSMenuItem.separator())

        // Quit
        let quitItem = NSMenuItem(
            title: "Quit",
            action: #selector(quit),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu

        // Update status if we have it
        if MediaKeyTap.isAccessibilityEnabled() {
            updateStatus("Status: Active ✓")
        }
    }

    @objc func configurationChanged() {
        NSLog("MacMediaKeys: Configuration changed, rebuilding menu")
        rebuildMenu()

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
        if let menu = statusItem.menu {
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

    @objc func openConfigureApps() {
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
        if let menu = statusItem.menu,
           let item = menu.item(withTag: 100) {
            item.title = text
        }
    }

    @objc func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func quit() {
        NSApplication.shared.terminate(nil)
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
