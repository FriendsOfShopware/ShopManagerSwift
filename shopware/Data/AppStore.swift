import Foundation

/// File-backed persistence of `AppData` (the Apple analogue of the Android DataStore at
/// `app-data.json`). Holds shops/auth/settings; written only on those changes. Snapshots live
/// in per-shop cache files (`SnapshotStore`) and are recombined by `AppRepository`.
actor AppStore {
    private let fileURL: URL
    private static let encoder = JSONEncoder()
    private static let decoder = JSONDecoder()

    init(directory: URL) {
        self.fileURL = directory.appendingPathComponent("app-data.json")
    }

    /// Reads and decodes, applying the legacy-demo-shop purge migration.
    func load() -> AppData {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? Self.decoder.decode(AppData.self, from: data) else {
            return AppData()
        }
        return Self.migrate(decoded)
    }

    func save(_ data: AppData) {
        guard let encoded = try? Self.encoder.encode(data) else { return }
        try? FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try? encoded.write(to: fileURL, options: .atomic)
    }

    /// Demo mode was removed — purge legacy demo shops persisted by older versions.
    private static func migrate(_ decoded: AppData) -> AppData {
        let demoIds = Set(decoded.shops.filter(\.demo).map(\.id))
        guard !demoIds.isEmpty else { return decoded }

        var migrated = decoded
        migrated.shops = decoded.shops.filter { !demoIds.contains($0.id) }
        migrated.snapshots = decoded.snapshots.filter { !demoIds.contains($0.key) }
        if let selected = decoded.selectedShopId, !demoIds.contains(selected) {
            migrated.selectedShopId = selected
        } else {
            migrated.selectedShopId = migrated.shops.first?.id
        }
        return migrated
    }
}
