import SwiftUI
import ShopwareAdminAPI

/// Dashboard quick edits use the same permissions, currency handling and retained
/// save flow as the full product workspace.
struct ProductActionSheet: View {
    let shop: ConnectedShop
    let productId: String
    @Environment(AppViewModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var vm: ProductDetailViewModel?
    var body: some View {
        Group {
            if let vm, let product = vm.product {
                ProductQuickEditorSheet(product: product, shop: shop, actions: vm.actions) { model.refresh(shop.id) }
            } else {
                NavigationStack {
                    Group {
                        if let error = vm?.error {
                            ContentUnavailableView { Label("Couldn't load product", systemImage: "exclamationmark.triangle") }
                            description: { Text(error) } actions: { Button("Retry") { Task { await vm?.load() } } }
                        } else { ProgressView("Loading product…") }
                    }
                    .navigationTitle("Quick edit")
                    .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } } }
                }
                #if os(macOS)
                .frame(minWidth: 460, idealWidth: 580, minHeight: 320, idealHeight: 500)
                #endif
            }
        }
        .task {
            let value = ProductDetailViewModel(api: model.repo.apiFor(shop), shop: shop, id: productId)
            vm = value; await value.load()
        }
    }
}
