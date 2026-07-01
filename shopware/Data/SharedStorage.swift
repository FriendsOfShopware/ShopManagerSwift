import Foundation

/// Resolves the on-disk directory that holds `app-data.json` and the per-shop `snapshots/` cache.
/// Prefers the App Group container (so a WidgetKit extension can read the same files cross-process);
/// falls back to Application Support when the group isn't provisioned (e.g. local dev / macOS).
enum SharedStorage {
    static let appGroupIdentifier = "group.de.shyim.shopware"

    static var containerURL: URL {
        if let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            return group
        }
        return URL.applicationSupportDirectory
    }
}
