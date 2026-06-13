import Foundation
import Testing
@testable import shopware

/// Verifies the widget cache-reading + formatting against fixture files (the Apple analogue of the
/// Android `WidgetDataTest`).
struct WidgetDataTests {
    private func tempDir() -> URL {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("widgettest-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func seed(_ dir: URL, appData: AppData, snapshots: [String: ShopSnapshot]) {
        let enc = JSONEncoder()
        var persisted = appData
        persisted.snapshots = [:]
        try? enc.encode(persisted).write(to: dir.appendingPathComponent("app-data.json"))
        let snapsDir = dir.appendingPathComponent("snapshots")
        try? FileManager.default.createDirectory(at: snapsDir, withIntermediateDirectories: true)
        for (id, snap) in snapshots {
            try? enc.encode(snap).write(to: snapsDir.appendingPathComponent("\(id).json"))
        }
    }

    @Test func todayWidgetReadsSelectedShop() {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        var shop = ConnectedShop(id: "abc", name: "Thread & Co", baseUrl: "https://x", currency: "EUR")
        shop.dailyTarget = 1000
        shop.tintIndex = 2
        var data = AppData()
        data.shops = [shop]
        data.selectedShopId = "abc"
        var snap = ShopSnapshot()
        snap.todayRevenue = 500
        snap.yesterdayRevenue = 250
        snap.lastSyncEpochMs = 123
        seed(dir, appData: data, snapshots: ["abc": snap])

        let state = WidgetData.readSelectedShopSnapshot(directory: dir)
        #expect(state != nil)
        #expect(state?.shopName == "Thread & Co")
        #expect(state?.deltaUp == true)        // 500 vs 250 → +100%
        #expect(state?.deltaLabel == "+100%")
        #expect(state?.targetPct == 0.5)       // 500 / 1000
        #expect(state?.tintIndex == 2)
        #expect(state?.lastSyncMs == 123)
    }

    @Test func weeklyWidgetComputesBarsAndMomentum() {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        var data = AppData()
        data.shops = [ConnectedShop(id: "s", name: "Shop", baseUrl: "https://x")]
        data.selectedShopId = "s"
        var snap = ShopSnapshot()
        snap.weekRevenue = [100, 100, 100, 200, 200, 200, 400] // max 400
        snap.todayIndex = 6
        seed(dir, appData: data, snapshots: ["s": snap])

        let state = WidgetData.readWeeklySnapshot(directory: dir)
        #expect(state != nil)
        #expect(state?.bars.last == 1.0)                 // 400/400
        #expect(state?.bars.first == 0.25)               // 100/400
        #expect(state?.todayIndex == 6)
        // momentum: 2nd half (200+200+400=800) vs 1st half (100+100+100=300) → up
        #expect(state?.deltaUp == true)
    }

    @Test func missingFilesReturnNil() {
        let dir = tempDir()
        defer { try? FileManager.default.removeItem(at: dir) }
        #expect(WidgetData.readSelectedShopSnapshot(directory: dir) == nil)
        #expect(WidgetData.readWeeklySnapshot(directory: dir) == nil)
    }
}
