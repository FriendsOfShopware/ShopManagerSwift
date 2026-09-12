import Testing
import SwiftUI
@testable import shopware

@MainActor
struct AppNavigationTests {
    private let full = ConnectedShop(id: "full", name: "Full", baseUrl: "https://navigation-ui.test")

    @Test func catalogAndSidebarRespectTheSamePermissions() {
        let limited = ConnectedShop(id: "limited", name: "Limited", baseUrl: full.baseUrl,
                                    scopes: ["order": false, "customer": false, "product": false,
                                             "promotion": false, "media": true, "product_review": false])
        #expect(Destination.compactTabs.filter { $0.isVisible(in: limited) } == [.home, .catalog])
        #expect(SidebarGroup.catalog.destinations.filter { $0.isVisible(in: limited) } == [.media])
        var none = limited
        none.scopes["media"] = false
        #expect(!Destination.catalog.isVisible(in: none))
    }

    @Test func shopSwitchClearsEveryPathAndFallsBackFromInaccessibleSections() {
        let navigation = AppNavigation()
        navigation.selection = .products
        navigation[.products].append("old-product")
        navigation[.home].append("old-order")
        let limited = ConnectedShop(id: "limited", name: "Limited", baseUrl: full.baseUrl, scopes: ["product": false])
        navigation.reset(for: limited)
        #expect(navigation.selection == .home)
        #expect(navigation.paths.isEmpty)
        navigation.selection = .customers
        navigation.reset(for: full)
        #expect(navigation.selection == .customers)
    }

    @Test func notificationWaitsForTheTargetShopAndRespectsOrderReadAccess() {
        let navigation = AppNavigation()
        navigation.selection = .catalog
        #expect(!navigation.openOrder("order", shopID: "other", in: full))
        #expect(navigation.selection == .catalog)
        #expect(navigation.openOrder("order", shopID: full.id, in: full))
        #expect(navigation.selection == .home)
        #expect(navigation[.home].count == 1)
        var denied = full
        denied.scopes["order"] = false
        #expect(navigation.openOrder("order", shopID: denied.id, in: denied))
        #expect(navigation[.home].isEmpty)
    }
}
