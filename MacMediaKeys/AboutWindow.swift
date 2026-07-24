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
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 340),
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
        mainStack.spacing = 8
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(mainStack)

        NSLayoutConstraint.activate([
            mainStack.topAnchor.constraint(equalTo: topAnchor, constant: 28),
            mainStack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            mainStack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
            mainStack.centerXAnchor.constraint(equalTo: centerXAnchor),
            mainStack.bottomAnchor.constraint(lessThanOrEqualTo: bottomAnchor, constant: -24)
        ])

        // App icon
        let iconView = NSImageView()
        iconView.image = NSApp.applicationIconImage
        iconView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            iconView.widthAnchor.constraint(equalToConstant: 80),
            iconView.heightAnchor.constraint(equalToConstant: 80)
        ])
        mainStack.addArrangedSubview(iconView)
        mainStack.setCustomSpacing(14, after: iconView)

        // App name
        let bundle = Bundle.main
        let appName = bundle.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? "MacMediaKeys"
        let nameLabel = NSTextField(labelWithString: appName)
        nameLabel.font = NSFont.systemFont(ofSize: 16, weight: .semibold)
        nameLabel.alignment = .center
        mainStack.addArrangedSubview(nameLabel)
        mainStack.setCustomSpacing(3, after: nameLabel)

        // Version
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "?"
        let versionLabel = NSTextField(labelWithString: "Version \(version) (\(build))")
        versionLabel.font = NSFont.systemFont(ofSize: 11)
        versionLabel.textColor = .secondaryLabelColor
        versionLabel.alignment = .center
        mainStack.addArrangedSubview(versionLabel)
        mainStack.setCustomSpacing(18, after: versionLabel)

        // Update status
        updateStatusLabel = NSTextField(labelWithString: "Checking for updates…")
        updateStatusLabel.font = NSFont.systemFont(ofSize: 11.5)
        updateStatusLabel.textColor = .secondaryLabelColor
        updateStatusLabel.alignment = .center
        mainStack.addArrangedSubview(updateStatusLabel)
        mainStack.setCustomSpacing(10, after: updateStatusLabel)

        updateActionButton = NSButton(title: "Install Update", target: self, action: #selector(updateActionClicked))
        updateActionButton.bezelStyle = .rounded
        updateActionButton.controlSize = .regular
        updateActionButton.isHidden = true
        mainStack.addArrangedSubview(updateActionButton)
        mainStack.setCustomSpacing(20, after: updateActionButton)

        // Separator
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        mainStack.addArrangedSubview(separator)
        NSLayoutConstraint.activate([
            separator.widthAnchor.constraint(equalTo: mainStack.widthAnchor)
        ])
        mainStack.setCustomSpacing(18, after: separator)

        // Credits — the two human credits align into a "label: name" table (like a
        // Finder Get Info panel) rather than each line centering independently, which
        // reads as noticeably more deliberate than three ragged, differently-indented rows.
        // Only the @username is a link — the name itself is plain text.
        let creditsGrid = NSGridView(views: [
            [creditPrefixLabel("Created by"), creditNameCell("Ray Hatfield", username: "@rayhatfield", profileURL: URL(string: "https://github.com/rayhatfield")!)],
            [creditPrefixLabel("With contributions from"), creditNameCell("Leopold Stenger", username: "@polderleo", profileURL: URL(string: "https://github.com/polderleo")!)]
        ])
        creditsGrid.rowSpacing = 3
        creditsGrid.columnSpacing = 5
        creditsGrid.column(at: 0).xPlacement = .trailing
        creditsGrid.column(at: 1).xPlacement = .leading
        mainStack.addArrangedSubview(creditsGrid)
        mainStack.setCustomSpacing(10, after: creditsGrid)

        // Built with Claude Code — its own quieter line, set apart from the human credits.
        let builtWithRow = NSStackView(views: [
            creditPrefixLabel("Built with", color: .tertiaryLabelColor),
            creditLinkButton("Claude Code", url: URL(string: "https://claude.com/claude-code")!, fontSize: 10.5)
        ])
        builtWithRow.orientation = .horizontal
        builtWithRow.spacing = 4
        mainStack.addArrangedSubview(builtWithRow)
        mainStack.setCustomSpacing(18, after: builtWithRow)

        // GitHub link
        let githubButton = NSButton(title: "View on GitHub", target: self, action: #selector(viewOnGitHubClicked))
        githubButton.image = NSImage(systemSymbolName: "arrow.up.right", accessibilityDescription: nil)
        githubButton.imagePosition = .imageTrailing
        githubButton.imageScaling = .scaleProportionallyDown
        githubButton.symbolConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .semibold)
        githubButton.isBordered = false
        githubButton.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        githubButton.contentTintColor = .linkColor
        mainStack.addArrangedSubview(githubButton)
    }

    private func creditPrefixLabel(_ text: String, color: NSColor = .secondaryLabelColor) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = color
        return label
    }

    /// A "Name (@username)" cell where only the @username is a clickable link to `profileURL`.
    private func creditNameCell(_ name: String, username: String, profileURL: URL) -> NSStackView {
        let nameLabel = NSTextField(labelWithString: "\(name) (")
        nameLabel.font = NSFont.systemFont(ofSize: 11)
        nameLabel.textColor = .labelColor

        let closingLabel = NSTextField(labelWithString: ")")
        closingLabel.font = NSFont.systemFont(ofSize: 11)
        closingLabel.textColor = .labelColor

        let linkButton = creditLinkButton(username, url: profileURL)

        let row = NSStackView(views: [nameLabel, linkButton, closingLabel])
        row.orientation = .horizontal
        row.spacing = 0
        // NSButton reserves title padding even when borderless; pull the
        // parentheses in so it reads as a tight "(@username)" rather than
        // "( @username )".
        row.setCustomSpacing(-4, after: nameLabel)
        row.setCustomSpacing(-4, after: linkButton)
        return row
    }

    /// A borderless, link-colored button used for a clickable credit name.
    private func creditLinkButton(_ title: String, url: URL, fontSize: CGFloat = 11) -> NSButton {
        let button = NSButton(title: title, target: self, action: #selector(creditLinkClicked(_:)))
        button.isBordered = false
        button.font = NSFont.systemFont(ofSize: fontSize)
        button.contentTintColor = .linkColor
        button.identifier = NSUserInterfaceItemIdentifier(url.absoluteString)
        return button
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
