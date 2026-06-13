import SwiftUI

// Temporary tab-screen stubs. Each is replaced by its real module as the port proceeds
// (Home/Reports → task 6, Orders → 7, Customers → 8, More modules → 9).

struct HomeView: View {
    let shop: ConnectedShop
    let onAddShop: () -> Void
    var body: some View {
        Text("Home — \(shop.name)").navigationTitle("Home")
    }
}

struct OrdersView: View {
    let shop: ConnectedShop
    var body: some View { Text("Orders").navigationTitle("Orders") }
}

struct CustomersView: View {
    let shop: ConnectedShop
    var body: some View { Text("Customers").navigationTitle("Customers") }
}

struct ReportsView: View {
    let shop: ConnectedShop
    var body: some View { Text("Reports").navigationTitle("Reports") }
}

struct MoreView: View {
    let shop: ConnectedShop
    var body: some View { Text("More").navigationTitle("More") }
}
