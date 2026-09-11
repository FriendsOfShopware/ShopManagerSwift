import SwiftUI

struct MediaView: View {
    @Environment(AppViewModel.self) private var model
    let shop: ConnectedShop
    @State private var vm: MediaViewModel?

    var body: some View {
        Group {
            if let vm, vm.shop.id == shop.id { MediaWorkspace(vm: vm).id(shop.id) }
            else { ProgressView("Loading media…") }
        }
        .task(id: shop.id) {
            guard vm?.shop.id != shop.id else { return }
            let next = MediaViewModel(repo: model.repo, shop: shop)
            vm = next
            await next.loadPermissions()
        }
    }
}
