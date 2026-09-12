import SwiftUI

struct OrderDetailView: View {
    @Environment(AppViewModel.self) private var model
    let shop: ConnectedShop
    let orderId: String
    @State private var vm: OrderDetailViewModel?

    var body: some View {
        Group {
            if let vm, vm.shop.id == shop.id, vm.orderId == orderId {
                if vm.detail != nil { OrderWorkspace(vm: vm) }
                else if let error = vm.error {
                    ContentUnavailableView {
                        Label("Couldn't load order", systemImage: "exclamationmark.triangle")
                    } description: { Text(error) } actions: {
                        Button("Retry") { Task { await vm.load() } }.accessibilityIdentifier("order.retry")
                    }
                } else { ProgressView("Loading order…") }
            } else { ProgressView("Loading order…") }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle(vm?.detail.map { "#" + $0.orderNumber } ?? String(localized: "Order"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task(id: "\(shop.id)|\(orderId)") {
            if vm?.shop.id != shop.id || vm?.orderId != orderId {
                vm = OrderDetailViewModel(repo: model.repo, shop: shop, orderId: orderId)
            }
            await vm?.load()
        }
    }
}
