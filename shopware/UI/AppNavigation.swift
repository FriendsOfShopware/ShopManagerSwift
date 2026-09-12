import SwiftUI

/// Per-window navigation shared by the sidebar and compact tab shell.
@Observable
final class AppNavigation {
    var selection: Destination = .home
    var paths: [Destination: NavigationPath] = [:]

    var sidebarSelection: Destination? {
        get { selection }
        set { if let newValue { selection = newValue } }
    }

    subscript(destination: Destination) -> NavigationPath {
        get { paths[destination] ?? NavigationPath() }
        set { paths[destination] = newValue }
    }

    func validateSelection(for shop: ConnectedShop) {
        if !selection.isVisible(in: shop) { selection = .home }
    }

    func reset(for shop: ConnectedShop) {
        paths.removeAll()
        validateSelection(for: shop)
    }

    /// Consume a notification only after its asynchronous shop switch has completed.
    @discardableResult
    func openOrder(_ orderID: String?, shopID: String, in shop: ConnectedShop) -> Bool {
        guard shopID == shop.id else { return false }
        selection = .home
        var path = NavigationPath()
        if let orderID, shop.canRead("order") { path.append(orderID) }
        paths[.home] = path
        return true
    }
}
