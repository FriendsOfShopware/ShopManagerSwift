import SwiftUI

struct ProductsView: View {
    let shop: ConnectedShop
    @Environment(AppViewModel.self) private var model
    @State private var vm: ProductsViewModel?
    var body: some View {
        Group {
            if let vm, let listing = vm.listing, let api = vm.api {
                ProductWorkspace(shop: shop, api: api, listing: listing).id("\(shop.id)|\(shop.languageId ?? "")")
            } else { ProgressView("Loading products…") }
        }
        .navigationTitle("Products")
        .task(id: "\(shop.id)|\(shop.languageId ?? "")") {
            await Task.yield()
            guard !Task.isCancelled else { return }
            if vm == nil { vm = ProductsViewModel(repo: model.repo) }
            vm?.start(shop)
        }
    }
}
