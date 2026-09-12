import SwiftUI

struct ShopSwitcher: View {
    @Environment(AppViewModel.self) private var model
    let shop: ConnectedShop
    let onAddShop: () -> Void
    var inSidebar = false
    @State private var showingManageShops = false

    var body: some View {
        Menu {
            ForEach(model.data.shops) { candidate in
                Button { model.selectShop(candidate.id) } label: {
                    Label(candidate.name, systemImage: candidate.id == shop.id ? "checkmark" : "storefront")
                }
                .accessibilityIdentifier("navigation.shop.\(candidate.id)")
            }
            Divider()
            Button("Add shop", systemImage: "plus", action: onAddShop)
            Button("Manage shops", systemImage: "gearshape") { showingManageShops = true }
                .accessibilityIdentifier("navigation.manageShops")
        } label: {
            HStack(spacing: 8) {
                if inSidebar { Image(systemName: "storefront").foregroundStyle(.tint) }
                Text(shop.name).font(.headline).lineLimit(inSidebar ? 2 : 1)
                if inSidebar { Spacer(minLength: 4) }
                Image(systemName: "chevron.down").font(.caption).foregroundStyle(.secondary)
            }
            .frame(minHeight: 44)
            .contentShape(.rect)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(Text(verbatim: shop.name))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: shop.name))
        .accessibilityIdentifier("navigation.shopSwitcher")
        .sheet(isPresented: $showingManageShops) {
            NavigationStack {
                ManageShopsView()
                    #if os(iOS)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Done") { showingManageShops = false }
                        }
                    }
                    #endif
            }
                #if os(macOS)
                .frame(minWidth: 480, idealWidth: 560, minHeight: 420, idealHeight: 560)
                #endif
                .acceptsFirstMouse()
        }
    }
}
