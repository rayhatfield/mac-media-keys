import Cocoa

/// Downloads the latest notarized release zip, verifies it was signed by the
/// same Developer ID team as this build, and atomically swaps it into place
/// over the running app, then relaunches. This is a lightweight stand-in for
/// a framework like Sparkle: no delta updates or EdDSA appcast signing, just
/// the GitHub release zip already published by `release-mac-media-keys` plus
/// Apple code signing as the authenticity check.
final class UpdateInstaller {
    static let shared = UpdateInstaller()

    /// The Developer ID team this app (and therefore any legitimate update) is signed with.
    private static let expectedTeamIdentifier = "C7U9V3BCYY"

    enum Stage {
        case downloading
        case verifying
        case installing
    }

    enum InstallError: Error {
        case downloadFailed
        case extractionFailed
        case noAppBundleFound
        case signatureMismatch
        case installFailed
    }

    /// The bits are always fully installed on disk by the time `install` succeeds —
    /// these two cases only distinguish whether the app also managed to relaunch itself.
    enum InstallOutcome {
        case relaunched
        /// The new version is installed, but relaunching it couldn't be confirmed, so
        /// the currently-running (old) instance was left alone rather than killed —
        /// the user needs to quit and reopen manually to pick up the new version.
        case manualRelaunchNeeded
    }

    /// Downloads, verifies, and installs the update at `downloadURL`. `progress` and
    /// `completion` are both called on the main queue. On success, attempts to relaunch
    /// into the new version automatically — see `InstallOutcome`.
    func install(from downloadURL: URL,
                  progress: @escaping (Stage) -> Void,
                  completion: @escaping (Result<InstallOutcome, InstallError>) -> Void) {
        progress(.downloading)

        let task = URLSession.shared.downloadTask(with: downloadURL) { tempFileURL, _, error in
            guard let tempFileURL = tempFileURL, error == nil else {
                debugLog("UpdateInstaller: download failed: \(error?.localizedDescription ?? "no file")")
                DispatchQueue.main.async { completion(.failure(.downloadFailed)) }
                return
            }

            // downloadTask deletes tempFileURL as soon as this closure returns, so
            // move it to a scratch dir we control before doing anything else.
            let scratchDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            let zipURL = scratchDir.appendingPathComponent("update.zip")
            let extractedDir = scratchDir.appendingPathComponent("extracted")

            do {
                try FileManager.default.createDirectory(at: scratchDir, withIntermediateDirectories: true)
                try FileManager.default.moveItem(at: tempFileURL, to: zipURL)
            } catch {
                debugLog("UpdateInstaller: failed to stage downloaded zip: \(error.localizedDescription)")
                DispatchQueue.main.async { completion(.failure(.downloadFailed)) }
                return
            }

            DispatchQueue.main.async { progress(.verifying) }

            guard Self.run("/usr/bin/ditto", ["-x", "-k", zipURL.path, extractedDir.path]) else {
                debugLog("UpdateInstaller: ditto extraction failed")
                try? FileManager.default.removeItem(at: scratchDir)
                DispatchQueue.main.async { completion(.failure(.extractionFailed)) }
                return
            }

            guard let appURL = try? FileManager.default.contentsOfDirectory(at: extractedDir, includingPropertiesForKeys: nil)
                .first(where: { $0.pathExtension == "app" }) else {
                debugLog("UpdateInstaller: no .app bundle found in extracted zip")
                try? FileManager.default.removeItem(at: scratchDir)
                DispatchQueue.main.async { completion(.failure(.noAppBundleFound)) }
                return
            }

            guard Self.verifySignature(of: appURL) else {
                debugLog("UpdateInstaller: signature verification failed for \(appURL.path)")
                try? FileManager.default.removeItem(at: scratchDir)
                DispatchQueue.main.async { completion(.failure(.signatureMismatch)) }
                return
            }

            DispatchQueue.main.async { progress(.installing) }

            let currentAppURL = Bundle.main.bundleURL
            do {
                _ = try FileManager.default.replaceItemAt(currentAppURL, withItemAt: appURL)
            } catch {
                debugLog("UpdateInstaller: install (replaceItemAt) failed: \(error.localizedDescription)")
                try? FileManager.default.removeItem(at: scratchDir)
                DispatchQueue.main.async { completion(.failure(.installFailed)) }
                return
            }

            try? FileManager.default.removeItem(at: scratchDir)

            DispatchQueue.main.async {
                Self.relaunch(at: currentAppURL) { didLaunch in
                    completion(.success(didLaunch ? .relaunched : .manualRelaunchNeeded))
                }
            }
        }
        task.resume()
    }

    /// Runs `codesign --verify` and confirms the extracted app is signed by the
    /// same Developer ID team as this running build.
    private static func verifySignature(of appURL: URL) -> Bool {
        guard run("/usr/bin/codesign", ["--verify", "--deep", "--strict", appURL.path]) else {
            return false
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["-dv", "--verbose=4", appURL.path]
        let stderrPipe = Pipe()
        process.standardError = stderrPipe
        process.standardOutput = Pipe()

        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()

        let output = String(data: stderrPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard let teamLine = output.split(separator: "\n").first(where: { $0.hasPrefix("TeamIdentifier=") }) else {
            return false
        }
        let teamIdentifier = teamLine.replacingOccurrences(of: "TeamIdentifier=", with: "")
        return teamIdentifier == expectedTeamIdentifier
    }

    /// Runs a command to completion, returning whether it exited successfully.
    @discardableResult
    private static func run(_ executablePath: String, _ arguments: [String]) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executablePath)
        process.arguments = arguments
        guard (try? process.run()) != nil else { return false }
        process.waitUntilExit()
        return process.terminationStatus == 0
    }

    /// Relaunches the freshly-installed app at `appURL`.
    ///
    /// This can't simply call `NSWorkspace.openApplication` and then terminate: AppKit
    /// treats the app as a single-instance bundle identifier, so while the old process
    /// is still alive, "launching" it just reactivates that same (stale, pre-update)
    /// instance instead of starting a fresh process from the updated bundle on disk.
    /// Instead we spawn a detached shell helper that waits for our own process to fully
    /// exit before running `open` on the new bundle, then terminate ourselves — the
    /// same ordering trick other macOS self-updaters (e.g. Sparkle) use.
    private static func relaunch(at appURL: URL, completion: @escaping (_ didLaunch: Bool) -> Void) {
        let pid = ProcessInfo.processInfo.processIdentifier
        // Poll for our own process to exit (max ~5s) before opening the new bundle,
        // so the open doesn't race a not-yet-dead old instance.
        let script = "i=0; while kill -0 \(pid) 2>/dev/null && [ $i -lt 50 ]; do sleep 0.1; i=$((i+1)); done; open \"\(appURL.path)\""

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]

        do {
            try process.run()
        } catch {
            debugLog("UpdateInstaller: failed to spawn relaunch helper: \(error.localizedDescription)")
            completion(false)
            return
        }

        completion(true)
        NSApp.terminate(nil)
    }
}
