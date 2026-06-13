import SwiftUI

// Temporary tab-screen stubs. Each is replaced by its real module as the port proceeds
// (Home/Reports → task 6, Orders → 7, Customers → 8, More modules → 9).

struct OrderDetailView: View {
    let shop: ConnectedShop
    let orderId: String
    var body: some View { Text("Order \(orderId)").navigationTitle("Order") }
}

struct ProductActionSheet: View {
    let shop: ConnectedShop
    let productId: String
    var body: some View { Text("Product \(productId)").presentationDetents([.medium]) }
}

struct ManageShopsView: View {
    var body: some View { Text("Manage shops").navigationTitle("Shops") }
}

struct OrdersView: View {
    let shop: ConnectedShop
    var body: some View { Text("Orders").navigationTitle("Orders") }
}

struct CustomersView: View {
    let shop: ConnectedShop
    var body: some View { Text("Customers").navigationTitle("Customers") }
}

struct MoreView: View {
    let shop: ConnectedShop
    var body: some View { Text("More").navigationTitle("More") }
}
