import SwiftUI

struct ProductDetailView: View {
    let shop: ConnectedShop
    let productId: String
    @Environment(AppViewModel.self) private var model
    @State private var vm: ProductDetailViewModel?
    var body: some View {
        Group {
            if let vm {
                if let product = vm.product { ProductDetailWorkspace(vm: vm, product: product) }
                else if let error = vm.error {
                    ContentUnavailableView { Label("Couldn't load product", systemImage: "exclamationmark.triangle") }
                    description: { Text(error) } actions: { Button("Retry") { Task { await vm.load() } } }
                } else { ProgressView("Loading product…") }
            } else { ProgressView("Loading product…") }
        }
        .navigationTitle(vm?.product?.name ?? String(localized: "Product"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task(id: "\(shop.id)|\(shop.languageId ?? "")|\(productId)") {
            let value = ProductDetailViewModel(api: model.repo.apiFor(shop), shop: shop, id: productId)
            vm = value; await value.load()
        }
    }
}
