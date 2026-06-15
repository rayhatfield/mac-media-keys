import Cocoa

/// Checks GitHub Releases for a newer version of the app and prompts the
/// user to download it. This is intentionally lightweight (no auto-install):
/// it just compares version numbers and opens the release page in a browser.
final class UpdateChecker {
    static let shared = UpdateChecker()

    private let releasesAPIURL = URL(string: "https://api.github.com/repos/rayhatfield/mac-media-keys/releases/latest")!
    private let releasesPageURL = URL(string: "https://github.com/rayhatfield/mac-media-keys/releases/latest")!

    /// Minimum time between automatic (silent) checks.
    private static let checkInterval: TimeInterval = 24 * 60 * 60

    private struct ReleaseInfo: Decodable {
        let tagName: String
        let htmlURL: String

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }

    /// Checks for updates.
    ///
    /// - Parameter userInitiated: if `true`, always shows a result alert
    ///   (including "you're up to date"), bypasses the skipped-version
    ///   preference, and ignores the check-interval throttle. If `false`,
    ///   only surfaces an alert when a new, non-skipped version is found,
    ///   and respects the check-interval throttle.
    func checkForUpdates(userInitiated: Bool) {
        let config = AppConfiguration.shared

        if !userInitiated {
            guard config.automaticUpdateChecksEnabled() else { return }

            if let last = config.lastUpdateCheckDate(),
               Date().timeIntervalSince(last) < Self.checkInterval {
                return
            }
        }

        config.setLastUpdateCheckDate(Date())

        let task = URLSession.shared.dataTask(with: releasesAPIURL) { data, response, error in
            if let error = error {
                debugLog("UpdateChecker: request failed: \(error.localizedDescription)")
                if userInitiated {
                    DispatchQueue.main.async {
                        self.showErrorAlert()
                    }
                }
                return
            }

            guard let data = data else { return }

            let release: ReleaseInfo
            do {
                release = try JSONDecoder().decode(ReleaseInfo.self, from: data)
            } catch {
                debugLog("UpdateChecker: failed to decode response: \(error.localizedDescription)")
                if userInitiated {
                    DispatchQueue.main.async {
                        self.showErrorAlert()
                    }
                }
                return
            }

            let latestVersion = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
            let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"

            debugLog("UpdateChecker: current=\(currentVersion) latest=\(latestVersion)")

            let releaseURL = URL(string: release.htmlURL) ?? self.releasesPageURL

            DispatchQueue.main.async {
                if Self.isVersion(latestVersion, newerThan: currentVersion) {
                    if !userInitiated && config.skippedUpdateVersion() == latestVersion {
                        debugLog("UpdateChecker: version \(latestVersion) was skipped, not prompting")
                        return
                    }
                    self.showUpdateAvailableAlert(latestVersion: latestVersion, releaseURL: releaseURL, userInitiated: userInitiated)
                } else if userInitiated {
                    self.showUpToDateAlert(currentVersion: currentVersion)
                }
            }
        }
        task.resume()
    }

    // MARK: - Alerts

    private func showUpdateAvailableAlert(latestVersion: String, releaseURL: URL, userInitiated: Bool) {
        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "Mac Media Keys \(latestVersion) is available. You're currently running \(currentVersionString())."
        alert.addButton(withTitle: "View Release")
        alert.addButton(withTitle: "Not Now")
        if !userInitiated {
            alert.addButton(withTitle: "Skip This Version")
        }

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()

        switch response {
        case .alertFirstButtonReturn:
            NSWorkspace.shared.open(releaseURL)
        case .alertThirdButtonReturn where !userInitiated:
            AppConfiguration.shared.setSkippedUpdateVersion(latestVersion)
        default:
            break
        }
    }

    private func showUpToDateAlert(currentVersion: String) {
        let alert = NSAlert()
        alert.messageText = "You're Up to Date"
        alert.informativeText = "Mac Media Keys \(currentVersion) is the latest version."
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func showErrorAlert() {
        let alert = NSAlert()
        alert.messageText = "Couldn't Check for Updates"
        alert.informativeText = "Please check your internet connection and try again."
        alert.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func currentVersionString() -> String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }

    // MARK: - Version Comparison

    /// Compares two dot-separated numeric version strings (e.g. "1.0.10" vs "1.0.9").
    /// Returns `true` if `lhs` is newer than `rhs`. Non-numeric or missing components
    /// are treated as `0`.
    static func isVersion(_ lhs: String, newerThan rhs: String) -> Bool {
        let lhsParts = lhs.split(separator: ".").map { Int($0) ?? 0 }
        let rhsParts = rhs.split(separator: ".").map { Int($0) ?? 0 }
        let count = max(lhsParts.count, rhsParts.count)

        for i in 0..<count {
            let l = i < lhsParts.count ? lhsParts[i] : 0
            let r = i < rhsParts.count ? rhsParts[i] : 0
            if l != r {
                return l > r
            }
        }
        return false
    }
}
