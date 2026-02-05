import Foundation

/// Manages app configuration including which built-in apps are enabled and custom apps added by the user
class AppConfiguration {
    static let shared = AppConfiguration()

    private let enabledBuiltInAppsKey = "EnabledBuiltInApps"
    private let customAppsKey = "CustomApps"
    private let selectedAppBundleIdKey = "SelectedAppBundleId"

    private init() {
        // Set default enabled apps if not configured
        if UserDefaults.standard.object(forKey: enabledBuiltInAppsKey) == nil {
            // Enable all built-in apps by default
            let defaultEnabled = MediaApp.allCases.map { $0.rawValue }
            UserDefaults.standard.set(defaultEnabled, forKey: enabledBuiltInAppsKey)
        }
    }

    // MARK: - Built-in Apps

    /// Get list of enabled built-in apps
    func enabledBuiltInApps() -> [MediaApp] {
        guard let enabledNames = UserDefaults.standard.stringArray(forKey: enabledBuiltInAppsKey) else {
            return MediaApp.allCases
        }
        return MediaApp.allCases.filter { enabledNames.contains($0.rawValue) }
    }

    /// Check if a built-in app is enabled
    func isBuiltInAppEnabled(_ app: MediaApp) -> Bool {
        guard let enabledNames = UserDefaults.standard.stringArray(forKey: enabledBuiltInAppsKey) else {
            return true
        }
        return enabledNames.contains(app.rawValue)
    }

    /// Enable or disable a built-in app
    func setBuiltInAppEnabled(_ app: MediaApp, enabled: Bool) {
        var enabledNames = UserDefaults.standard.stringArray(forKey: enabledBuiltInAppsKey) ?? MediaApp.allCases.map { $0.rawValue }

        if enabled {
            if !enabledNames.contains(app.rawValue) {
                enabledNames.append(app.rawValue)
            }
        } else {
            enabledNames.removeAll { $0 == app.rawValue }
        }

        UserDefaults.standard.set(enabledNames, forKey: enabledBuiltInAppsKey)
        NotificationCenter.default.post(name: .appConfigurationChanged, object: nil)
    }

    // MARK: - Custom Apps

    /// Get list of custom apps added by the user
    func customApps() -> [CustomMediaApp] {
        guard let data = UserDefaults.standard.data(forKey: customAppsKey),
              let apps = try? JSONDecoder().decode([CustomMediaApp].self, from: data) else {
            return []
        }
        return apps
    }

    /// Add a custom app
    func addCustomApp(_ app: CustomMediaApp) {
        var apps = customApps()
        // Don't add duplicates
        if !apps.contains(where: { $0.bundleIdentifier == app.bundleIdentifier }) {
            apps.append(app)
            saveCustomApps(apps)
            NotificationCenter.default.post(name: .appConfigurationChanged, object: nil)
        }
    }

    /// Remove a custom app
    func removeCustomApp(_ app: CustomMediaApp) {
        var apps = customApps()
        apps.removeAll { $0.bundleIdentifier == app.bundleIdentifier }
        saveCustomApps(apps)
        NotificationCenter.default.post(name: .appConfigurationChanged, object: nil)
    }

    private func saveCustomApps(_ apps: [CustomMediaApp]) {
        if let data = try? JSONEncoder().encode(apps) {
            UserDefaults.standard.set(data, forKey: customAppsKey)
        }
    }

    // MARK: - All Available Apps

    /// Get all apps that should appear in the menu (enabled built-in + custom)
    func allAvailableApps() -> [CustomMediaApp] {
        var apps: [CustomMediaApp] = []

        // Add enabled built-in apps
        for builtIn in enabledBuiltInApps() {
            apps.append(builtIn.toCustomApp())
        }

        // Add custom apps
        apps.append(contentsOf: customApps())

        return apps
    }

    // MARK: - Selected App

    /// Get the currently selected app's bundle identifier
    func selectedAppBundleId() -> String? {
        return UserDefaults.standard.string(forKey: selectedAppBundleIdKey)
    }

    /// Set the selected app by bundle identifier
    func setSelectedAppBundleId(_ bundleId: String) {
        UserDefaults.standard.set(bundleId, forKey: selectedAppBundleIdKey)
    }

    /// Get the currently selected app, or default to first available
    func selectedApp() -> CustomMediaApp? {
        let available = allAvailableApps()
        if let bundleId = selectedAppBundleId(),
           let app = available.first(where: { $0.bundleIdentifier == bundleId }) {
            return app
        }
        return available.first
    }
}

// MARK: - Notification

extension Notification.Name {
    static let appConfigurationChanged = Notification.Name("AppConfigurationChanged")
}
