import Cocoa

class ConfigureAppsWindowController: NSWindowController {
    static var shared: ConfigureAppsWindowController?

    static func show() {
        if shared == nil {
            shared = ConfigureAppsWindowController()
        }
        shared?.showWindow(nil)
        shared?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 350),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Configure Apps"
        window.center()
        window.isReleasedWhenClosed = false

        self.init(window: window)

        let contentView = ConfigureAppsView(frame: window.contentView!.bounds)
        contentView.autoresizingMask = [.width, .height]
        window.contentView = contentView
    }
}

class ConfigureAppsView: NSView {
    private var builtInCheckboxes: [MediaApp: NSButton] = [:]
    private var customAppsStackView: NSStackView!
    private let config = AppConfiguration.shared

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
    }

    private func setupUI() {
        // Main stack view
        let mainStack = NSStackView()
        mainStack.orientation = .vertical
        mainStack.alignment = .leading
        mainStack.spacing = 16
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: topAnchor, constant: 20),
            mainStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 20),
            mainStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -20),
            mainStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -20)
        ])

        // Built-in Apps Section
        let builtInLabel = NSTextField(labelWithString: "Built-in Apps")
        builtInLabel.font = NSFont.boldSystemFont(ofSize: 13)
        mainStack.addArrangedSubview(builtInLabel)

        let builtInDescription = NSTextField(wrappingLabelWithString: "Select which built-in apps to show in the menu:")
        builtInDescription.font = NSFont.systemFont(ofSize: 11)
        builtInDescription.textColor = .secondaryLabelColor
        mainStack.addArrangedSubview(builtInDescription)

        // Checkboxes for built-in apps
        for app in MediaApp.allCases {
            let checkbox = NSButton(checkboxWithTitle: app.displayName, target: self, action: #selector(builtInAppToggled(_:)))
            checkbox.state = config.isBuiltInAppEnabled(app) ? .on : .off
            builtInCheckboxes[app] = checkbox
            mainStack.addArrangedSubview(checkbox)
        }

        // Separator
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        mainStack.addArrangedSubview(separator)
        NSLayoutConstraint.activate([
            separator.widthAnchor.constraint(equalTo: mainStack.widthAnchor)
        ])

        // Custom Apps Section
        let customLabel = NSTextField(labelWithString: "Custom Apps")
        customLabel.font = NSFont.boldSystemFont(ofSize: 13)
        mainStack.addArrangedSubview(customLabel)

        let customDescription = NSTextField(wrappingLabelWithString: "Add other media apps to control with your media keys:")
        customDescription.font = NSFont.systemFont(ofSize: 11)
        customDescription.textColor = .secondaryLabelColor
        mainStack.addArrangedSubview(customDescription)

        // Stack view for custom apps
        customAppsStackView = NSStackView()
        customAppsStackView.orientation = .vertical
        customAppsStackView.alignment = .leading
        customAppsStackView.spacing = 8
        mainStack.addArrangedSubview(customAppsStackView)

        refreshCustomAppsList()

        // Add App button
        let addButton = NSButton(title: "Add App...", target: self, action: #selector(addAppClicked))
        addButton.bezelStyle = .rounded
        mainStack.addArrangedSubview(addButton)
    }

    @objc private func builtInAppToggled(_ sender: NSButton) {
        for (app, checkbox) in builtInCheckboxes {
            if checkbox == sender {
                config.setBuiltInAppEnabled(app, enabled: sender.state == .on)
                break
            }
        }
    }

    @objc private func addAppClicked() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.message = "Select a media application to add"

        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            self?.addAppFromURL(url)
        }
    }

    private func addAppFromURL(_ url: URL) {
        // Get bundle info from the app
        guard let bundle = Bundle(url: url),
              let bundleId = bundle.bundleIdentifier else {
            showAlert(message: "Could not read app bundle information.")
            return
        }

        // Get display name
        let displayName = bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? url.deletingPathExtension().lastPathComponent

        // Check if already added
        if config.customApps().contains(where: { $0.bundleIdentifier == bundleId }) {
            showAlert(message: "\(displayName) is already in your list.")
            return
        }

        // Check if it's a built-in app
        if MediaApp.allCases.contains(where: { $0.bundleIdentifier == bundleId }) {
            showAlert(message: "\(displayName) is a built-in app. Use the checkboxes above to enable it.")
            return
        }

        let customApp = CustomMediaApp(displayName: displayName, bundleIdentifier: bundleId)
        config.addCustomApp(customApp)
        refreshCustomAppsList()
    }

    private func refreshCustomAppsList() {
        // Remove existing views
        for view in customAppsStackView.arrangedSubviews {
            customAppsStackView.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        let customApps = config.customApps()

        if customApps.isEmpty {
            let emptyLabel = NSTextField(labelWithString: "No custom apps added yet.")
            emptyLabel.font = NSFont.systemFont(ofSize: 11)
            emptyLabel.textColor = .tertiaryLabelColor
            customAppsStackView.addArrangedSubview(emptyLabel)
        } else {
            for app in customApps {
                let rowStack = NSStackView()
                rowStack.orientation = .horizontal
                rowStack.spacing = 8

                let nameLabel = NSTextField(labelWithString: app.displayName)
                nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)

                let removeButton = NSButton(title: "Remove", target: self, action: #selector(removeAppClicked(_:)))
                removeButton.bezelStyle = .rounded
                removeButton.controlSize = .small
                removeButton.identifier = NSUserInterfaceItemIdentifier(app.bundleIdentifier)

                rowStack.addArrangedSubview(nameLabel)
                rowStack.addArrangedSubview(removeButton)

                customAppsStackView.addArrangedSubview(rowStack)
            }
        }
    }

    @objc private func removeAppClicked(_ sender: NSButton) {
        guard let bundleId = sender.identifier?.rawValue else { return }

        if let app = config.customApps().first(where: { $0.bundleIdentifier == bundleId }) {
            config.removeCustomApp(app)
            refreshCustomAppsList()
        }
    }

    private func showAlert(message: String) {
        let alert = NSAlert()
        alert.messageText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
