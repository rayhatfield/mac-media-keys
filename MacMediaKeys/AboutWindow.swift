import Cocoa

private let githubRepoURL = URL(string: "https://github.com/rayhatfield/mac-media-keys")!

class AboutWindowController: NSWindowController {
    static var shared: AboutWindowController?

    static func show() {
        if shared == nil {
            shared = AboutWindowController()
        }
        shared?.showWindow(nil)
        shared?.window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    convenience init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 380),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "About MacMediaKeys"
        window.center()
        window.isReleasedWhenClosed = false

        self.init(window: window)

        let contentView = AboutView(frame: window.contentView!.bounds)
        contentView.autoresizingMask = [.width, .height]
        window.contentView = contentView
    }
}

class AboutView: NSView {
    private enum UpdateAction {
        case install(downloadURL: URL, releaseURL: URL)
        case viewRelease(releaseURL: URL)
    }

    private var updateStatusLabel: NSTextField!
    private var updateActionButton: NSButton!
    private var updateAction: UpdateAction?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        setupUI()
        checkForUpdates()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupUI()
        checkForUpdates()
    }

    private func setupUI() {
        let mainStack = NSStackView()
        mainStack.orientation = .vertical
        mainStack.alignment = .centerX
        mainStack.spacing = 10
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: topAnchor, constant: 24),
            mainStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 20),
            mainStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -20),
            mainStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            mainStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -20)
        ])

        // App icon
        let iconView = NSImageView()
        iconView.image = NSApp.applicationIconImage
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 64),
            iconView.heightAnchor.constraint(equalToConstant: 64)
        ])
        mainStack.addArrangedSubview(iconView)

        // App name
        let bundle = Bundle.main
        let appName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? "MacMediaKeys"
        let nameLabel = NSTextField(labelWithString: appName)
        nameLabel.font = NSFont.boldSystemFont(ofSize: 15)
        mainStack.addArrangedSubview(nameLabel)

        // Version
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let versionLabel = NSTextField(labelWithString: "Version \(version) (build \(build))")
        versionLabel.font = NSFont.systemFont(ofSize: 11)
        versionLabel.textColor = .secondaryLabelColor
        mainStack.addArrangedSubview(versionLabel)

        // Update status
        updateStatusLabel = NSTextField(labelWithString: "Checking for updates…")
        updateStatusLabel.font = NSFont.systemFont(ofSize: 11)
        updateStatusLabel.textColor = .secondaryLabelColor
        mainStack.addArrangedSubview(updateStatusLabel)

        updateActionButton = NSButton(title: "Install Update", target: self, action: #selector(updateActionClicked))
        updateActionButton.bezelStyle = .rounded
        updateActionButton.controlSize = .small
        updateActionButton.isHidden = true
        mainStack.addArrangedSubview(updateActionButton)

        // Separator
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        mainStack.addArrangedSubview(separator)
        NSLayoutConstraint.activate([
            separator.widthAnchor.constraint(equalTo: mainStack.widthAnchor)
        ])
        mainStack.setCustomSpacing(16, after: separator)

        // Credits
        let creditsStack = NSStackView()
        creditsStack.orientation = .vertical
        creditsStack.alignment = .centerX
        creditsStack.spacing = 4
        creditsStack.addArrangedSubview(creditRow(
            prefix: "Created by",
            name: "Ray Hatfield",
            url: URL(string: "https://github.com/rayhatfield")!
        ))
        creditsStack.addArrangedSubview(creditRow(
            prefix: "With contributions from",
            name: "Leopold Stenger (@polderleo)",
            url: URL(string: "https://github.com/polderleo")!
        ))
        creditsStack.addArrangedSubview(creditRow(
            prefix: "Built with",
            name: "Claude Code",
            url: URL(string: "https://claude.com/claude-code")!
        ))
        mainStack.addArrangedSubview(creditsStack)

        // GitHub link
        let githubButton = NSButton(title: "View on GitHub", target: self, action: #selector(viewOnGitHubClicked))
        githubButton.isBordered = false
        githubButton.font = NSFont.systemFont(ofSize: 12)
        githubButton.contentTintColor = .linkColor
        mainStack.addArrangedSubview(githubButton)
    }

    /// Builds a "<prefix> <name>" row where <name> is a clickable link to `url`.
    private func creditRow(prefix: String, name: String, url: URL) -> NSStackView {
        let row = NSStackView()
        row.orientation = .horizontal
        row.spacing = 4

        let prefixLabel = NSTextField(labelWithString: prefix)
        prefixLabel.font = NSFont.systemFont(ofSize: 11)
        prefixLabel.textColor = .secondaryLabelColor
        row.addArrangedSubview(prefixLabel)

        let nameButton = NSButton(title: name, target: self, action: #selector(creditLinkClicked(_:)))
        nameButton.isBordered = false
        nameButton.font = NSFont.systemFont(ofSize: 11)
        nameButton.contentTintColor = .linkColor
        nameButton.identifier = NSUserInterfaceItemIdentifier(url.absoluteString)
        row.addArrangedSubview(nameButton)

        return row
    }

    @objc private func creditLinkClicked(_ sender: NSButton) {
        guard let raw = sender.identifier?.rawValue, let url = URL(string: raw) else { return }
        NSWorkspace.shared.open(url)
    }

    private func checkForUpdates() {
        UpdateChecker.shared.checkStatus { [weak self] status in
            guard let self = self else { return }
            switch status {
            case .upToDate:
                self.updateStatusLabel.stringValue = "You're up to date."
                self.updateActionButton.isHidden = true
            case .available(let version, let releaseURL, let downloadURL):
                self.updateStatusLabel.stringValue = "Update available: v\(version)"
                if let downloadURL = downloadURL {
                    self.updateAction = .install(downloadURL: downloadURL, releaseURL: releaseURL)
                    self.updateActionButton.title = "Install Update"
                } else {
                    self.updateAction = .viewRelease(releaseURL: releaseURL)
                    self.updateActionButton.title = "View Release"
                }
                self.updateActionButton.isEnabled = true
                self.updateActionButton.isHidden = false
            case .error:
                self.updateStatusLabel.stringValue = "Couldn't check for updates."
                self.updateActionButton.isHidden = true
            }
        }
    }

    @objc private func updateActionClicked() {
        switch updateAction {
        case .install(let downloadURL, let releaseURL):
            beginInstall(from: downloadURL, releaseURLFallback: releaseURL)
        case .viewRelease(let releaseURL):
            NSWorkspace.shared.open(releaseURL)
        case nil:
            break
        }
    }

    private func beginInstall(from downloadURL: URL, releaseURLFallback: URL) {
        updateActionButton.isEnabled = false

        UpdateInstaller.shared.install(from: downloadURL, progress: { [weak self] stage in
            guard let self = self else { return }
            switch stage {
            case .downloading:
                self.updateStatusLabel.stringValue = "Downloading update…"
            case .verifying:
                self.updateStatusLabel.stringValue = "Verifying update…"
            case .installing:
                self.updateStatusLabel.stringValue = "Installing update…"
            }
        }, completion: { [weak self] result in
            guard let self = self else { return }
            switch result {
            case .success(.relaunched):
                self.updateStatusLabel.stringValue = "Installed — relaunching…"
            case .success(.manualRelaunchNeeded):
                self.updateStatusLabel.stringValue = "Update installed. Quit and reopen MacMediaKeys to finish."
                self.updateActionButton.isHidden = true
            case .failure:
                self.updateStatusLabel.stringValue = "Couldn't install update automatically."
                self.updateAction = .viewRelease(releaseURL: releaseURLFallback)
                self.updateActionButton.title = "View Release"
                self.updateActionButton.isEnabled = true
            }
        })
    }

    @objc private func viewOnGitHubClicked() {
        NSWorkspace.shared.open(githubRepoURL)
    }
}
