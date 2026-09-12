import SwiftUI

struct PromotionDetailView: View {
    let shop: ConnectedShop
    let promotionID: String
    @Environment(AppViewModel.self) private var model
    @State private var vm: PromotionDetailViewModel?
    var body: some View {
        Group {
            if let vm {
                if let promotion = vm.promotion { PromotionDetailWorkspace(vm: vm, promotion: promotion) }
                else if let error = vm.error {
                    ContentUnavailableView { Label("Couldn't load promotion", systemImage: "exclamationmark.triangle") }
                    description: { Text(error) } actions: { Button("Retry") { Task { await vm.load() } } }
                } else { ProgressView("Loading promotion…") }
            } else { ProgressView("Loading promotion…") }
        }
        .navigationTitle(vm?.promotion?.name ?? String(localized: "Promotion"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task(id: "\(shop.id)|\(shop.languageId ?? "")|\(promotionID)") {
            let value = PromotionDetailViewModel(api: model.repo.apiFor(shop), shop: shop, id: promotionID)
            vm = value; await value.load()
        }
    }
}
