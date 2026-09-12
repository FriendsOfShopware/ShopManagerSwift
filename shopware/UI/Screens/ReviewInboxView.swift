import SwiftUI
import ShopwareAdminAPI

struct ReviewInboxView: View {
    let shop: ConnectedShop
    @Environment(AppViewModel.self) private var model
    @State private var vm: ReviewInboxViewModel?
    var body: some View {
        Group {
            if let vm, let listing = vm.listing, let api = vm.api {
                ReviewWorkspace(shop: shop, api: api, listing: listing)
                    .id("\(shop.id)|\(shop.languageId ?? "")")
            } else { ProgressView("Loading reviews…") }
        }
        .navigationTitle("Reviews")
        .task(id: "\(shop.id)|\(shop.languageId ?? "")") {
            // macOS may discard a transient navigation view while sizing a new window.
            // Let SwiftUI cancel that task before starting a listing request.
            await Task.yield()
            guard !Task.isCancelled else { return }
            if vm == nil { vm = ReviewInboxViewModel(repo: model.repo) }
            vm?.start(shop)
        }
    }
}
