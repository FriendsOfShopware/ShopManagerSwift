import Foundation

/// Bundle lookup is available in Foundation on both Apple platforms and Linux.
/// The package owns its English and German resources independently of the app.
func apiLocalized(_ key: String) -> String {
    Bundle.module.localizedString(forKey: key, value: nil, table: nil)
}
