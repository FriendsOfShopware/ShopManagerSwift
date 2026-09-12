import SwiftUI

struct PromosView: View {
    let shop: ConnectedShop
    @Environment(AppViewModel.self) private var model
    @State private var vm: PromotionsViewModel?
    var body: some View {
        Group {
            if let vm, let listing = vm.listing, let api = vm.api {
                PromotionWorkspace(shop: shop, api: api, listing: listing).id("\(shop.id)|\(shop.languageId ?? "")")
            } else { ProgressView("Loading promotions…") }
        }
        .navigationTitle("Promotions")
        .task(id: "\(shop.id)|\(shop.languageId ?? "")") {
            await Task.yield()
            guard !Task.isCancelled else { return }
            if vm == nil { vm = PromotionsViewModel(repo: model.repo) }
            vm?.start(shop)
        }
    }
}
