import SwiftUI

/// Lists the connected shops; each row opens its per-shop settings. An Add button and empty-state
/// launch the connect wizard.
struct ManageShopsView: View {
    @Environment(AppViewModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var showingConnect = false
    @State private var pendingRemoval: ConnectedShop?

    var body: some View {
        Group {
            if model.data.shops.isEmpty {
                ContentUnavailableView {
                    Label("No shops", systemImage: "storefront")
                } description: {
                    Text("Connect a Shopware shop to get started.")
                } actions: {
                    Button("Add shop") { showingConnect = true }
                        .buttonStyle(.borderedProminent)
                }
            } else {
                List {
                    ForEach(model.data.shops) { shop in
                        NavigationLink(value: ShopSettingsRoute(id: shop.id)) {
                            HStack(spacing: 12) {
                                ShopIconBox(tint: shop.tint, size: 36)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(shop.name).font(.subheadline.weight(.medium))
                                    Text(shop.baseUrl.replacingOccurrences(of: "https://", with: ""))
                                        .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                            }
                        }
                        #if os(iOS)
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button("Remove", systemImage: "trash", role: .destructive) { pendingRemoval = shop }
                        }
                        #endif
                        .contextMenu {
                            Button("Remove", systemImage: "trash", role: .destructive) { pendingRemoval = shop }
                        }
                    }
                }
                .groupedListStyle()
            }
        }
        .navigationTitle("Shops")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { showingConnect = true } label: { Label("Add shop", systemImage: "plus") }
            }
            #if os(macOS)
            // On macOS a sheet has no default dismiss chrome — provide an explicit Done.
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
            #endif
        }
        .navigationDestination(for: ShopSettingsRoute.self) { route in
            if let shop = model.shop(route.id) {
                ShopSettingsView(shop: shop)
            }
        }
        .sheet(isPresented: $showingConnect) {
            ConnectView(onClose: { showingConnect = false }, onFinished: { shopId in
                showingConnect = false
                model.refresh(shopId)
                model.reregisterPush()
            })
            .environment(model)
        }
        .alert(item: $pendingRemoval) { shop in
            Alert(
                title: Text("Remove \(shop.name)?"),
                message: Text("This disconnects the shop and clears its stored credentials on this device."),
                primaryButton: .destructive(Text("Remove")) { model.removeShop(shop.id) },
                secondaryButton: .cancel()
            )
        }
    }
}

struct ShopSettingsRoute: Hashable { let id: String }
