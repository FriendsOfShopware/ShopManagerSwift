import SwiftUI
import ShopwareAdminAPI

struct CustomersView: View {
    @Environment(AppViewModel.self) private var model
    let shop: ConnectedShop
    @State private var vm: CustomersViewModel?

    @State private var navCustomerId: String?

    var body: some View {
        Group {
            if let vm, let listing = vm.listing {
                listingContent(listing)
                    .navigationDestination(for: CustomerRoute.self) { route in
                        CustomerDetailView(shop: shop, customerId: route.id, onSaved: { listing.reload() })
                    }
                    .navigationDestination(for: String.self) { orderId in
                        OrderDetailView(shop: shop, orderId: orderId)
                    }
            } else {
                ProgressView()
            }
        }
        .navigationDestination(item: $navCustomerId) { id in
            CustomerDetailView(shop: shop, customerId: id, onSaved: { vm?.listing?.reload() })
        }
        .navigationTitle("Customers")
        .onAppear {
            if vm == nil { vm = CustomersViewModel(repo: model.repo) }
            vm?.start(shop)
        }
        .task(id: shop.id) {
            if vm == nil { vm = CustomersViewModel(repo: model.repo) }
            vm?.start(shop)
            await vm?.loadPermissions()
        }
    }

    @ViewBuilder
    private func listingContent(_ listing: ListingState<CustomerRow>) -> some View {
        #if os(macOS)
        if let vm {
            MacCustomersTable(vm: vm, shop: shop, listing: listing, onOpen: { navCustomerId = $0 })
                .id(shop.id)
        }
        #elseif os(iOS)
        if let vm {
            MobileCustomersList(vm: vm, shop: shop, listing: listing, onOpen: { navCustomerId = $0 })
                .id(shop.id)
        }
        #endif
    }

}
