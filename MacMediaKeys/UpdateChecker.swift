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
        let assets: [Asset]

        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: String

            enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case assets
        }
    }

    /// Result of comparing the latest GitHub release against the running version.
    enum UpdateStatus {
        case upToDate
        /// `downloadURL` is the release's `.zip` asset, for in-app installation. `nil`
        /// only if the release unexpectedly has no zip asset — callers should fall
        /// back to opening `releaseURL` in that case.
        case available(version: String, releaseURL: URL, downloadURL: URL?)
        case error
    }

    /// Fetches the latest GitHub release and compares it against the current version.
    /// Always performs a fresh network request — no throttling, no skipped-version
    /// check, and never shows an alert. Completion is called on the main queue.
    func checkStatus(completion: @escaping (UpdateStatus) -> Void) {
        fetchLatestRelease { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let release):
                    let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
                    if Self.isVersion(release.version, newerThan: currentVersion) {
                        completion(.available(version: release.version, releaseURL: release.url, downloadURL: release.downloadURL))
                    } else {
                        completion(.upToDate)
                    }
                case .failure:
                    completion(.error)
                }
            }
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

        fetchLatestRelease { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let release):
                    if Self.isVersion(release.version, newerThan: release.currentVersion) {
                        if !userInitiated && config.skippedUpdateVersion() == release.version {
                            debugLog("UpdateChecker: version \(release.version) was skipped, not prompting")
                            return
                        }
                        self.showUpdateAvailableAlert(latestVersion: release.version, userInitiated: userInitiated)
                    } else if userInitiated {
                        self.showUpToDateAlert(currentVersion: release.currentVersion)
                    }
                case .failure:
                    if userInitiated {
                        self.showErrorAlert()
                    }
                }
            }
        }
    }

    /// Fetches and decodes the latest GitHub release. Calls `completion` on a
    /// background queue with the resolved version/URL, or an error.
    private func fetchLatestRelease(completion: @escaping (Result<(version: String, currentVersion: String, url: URL, downloadURL: URL?), Error>) -> Void) {
        let task = URLSession.shared.dataTask(with: releasesAPIURL) { data, response, error in
            if let error = error {
                debugLog("UpdateChecker: request failed: \(error.localizedDescription)")
                completion(.failure(error))
                return
            }

            guard let data = data else {
                completion(.failure(URLError(.badServerResponse)))
                return
            }

            do {
                let release = try JSONDecoder().decode(ReleaseInfo.self, from: data)
                let latestVersion = release.tagName.hasPrefix("v") ? String(release.tagName.dropFirst()) : release.tagName
                let currentVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
                let releaseURL = URL(string: release.htmlURL) ?? self.releasesPageURL
                let downloadURL = release.assets
                    .first { $0.name.hasSuffix(".zip") }
                    .flatMap { URL(string: $0.browserDownloadURL) }

                debugLog("UpdateChecker: current=\(currentVersion) latest=\(latestVersion)")
                completion(.success((version: latestVersion, currentVersion: currentVersion, url: releaseURL, downloadURL: downloadURL)))
            } catch {
                debugLog("UpdateChecker: failed to decode response: \(error.localizedDescription)")
                completion(.failure(error))
            }
        }
        task.resume()
    }

    // MARK: - Alerts

    private func showUpdateAvailableAlert(latestVersion: String, userInitiated: Bool) {
        let alert = NSAlert()
        alert.messageText = "Update Available"
        alert.informativeText = "Mac Media Keys \(latestVersion) is available. You're currently running \(currentVersionString())."
        alert.addButton(withTitle: "Install Update")
        alert.addButton(withTitle: "Not Now")
        if !userInitiated {
            alert.addButton(withTitle: "Skip This Version")
        }

        NSApp.activate(ignoringOtherApps: true)
        let response = alert.runModal()

        switch response {
        case .alertFirstButtonReturn:
            // The About window re-checks and drives the actual install/progress UI.
            AboutWindowController.show()
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
