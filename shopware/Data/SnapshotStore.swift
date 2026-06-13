import Foundation

/// Per-shop snapshot cache, one JSON file per shop ({shopId}.json). Snapshots are re-fetchable
/// overview data: keeping them out of app-data.json means the frequent background sync never
/// rewrites credentials/settings, and a corrupt cache file costs one shop's cache instead of
/// every connection.
struct SnapshotStore: Sendable {
    let dir: URL

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        return e
    }()
    private static let decoder = JSONDecoder()

    /// shopId is always an app-generated UUID hex string, safe as a file name.
    private func fileFor(_ shopId: String) -> URL {
        dir.appendingPathComponent("\(shopId).json")
    }

    func loadAll() -> [String: ShopSnapshot] {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else { return [:] }

        var result: [String: ShopSnapshot] = [:]
        for file in files where file.pathExtension == "json" {
            let id = file.deletingPathExtension().lastPathComponent
            do {
                let data = try Data(contentsOf: file)
                result[id] = try Self.decoder.decode(ShopSnapshot.self, from: data)
            } catch {
                // corrupt cache — drop it, the next refresh rebuilds it
                try? FileManager.default.removeItem(at: file)
            }
        }
        return result
    }

    func write(_ shopId: String, _ snapshot: ShopSnapshot) {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? Self.encoder.encode(snapshot) else { return }
        let target = fileFor(shopId)
        let tmp = dir.appendingPathComponent("\(shopId).json.tmp")
        do {
            try data.write(to: tmp, options: .atomic)
            // Replace existing file atomically.
            _ = try FileManager.default.replaceItemAt(target, withItemAt: tmp)
        } catch {
            // fall back to a direct write
            try? data.write(to: target, options: .atomic)
            try? FileManager.default.removeItem(at: tmp)
        }
    }

    func delete(_ shopId: String) {
        try? FileManager.default.removeItem(at: fileFor(shopId))
    }
}
