import SwiftUI
import ShopwareAdminAPI

struct CustomerWorkspace: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Bindable var vm: CustomerDetailViewModel
    let onSaved: () -> Void
    @State private var tab: CustomerDetailTab = .general
    @State private var creatingOrder = false
    @State private var createdOrderId: String?

    var body: some View {
        VStack(spacing: 0) {
            if let detail = vm.detail {
                if let error = vm.error {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).padding()
                }
                switch tab {
                case .general:
                    CustomerProfileContent(shop: vm.shop, detail: detail, orderTotalCount: vm.orderTotalCount, api: vm.api, customFieldSets: vm.customFieldSets) {
                        tab = .addresses
                    }
                    .refreshable { await vm.load() }
                case .addresses:
                    CustomerAddressesView(vm: vm, onSaved: onSaved)
                case .orders:
                    if let orders = vm.orders {
                        CustomerOrderHistory(shop: vm.shop, orders: orders,
                                                  canCreateOrder: vm.permissions.allows("order:create") && vm.permissions.allows("api_proxy_switch-customer")) {
                            creatingOrder = true
                        }
                    } else {
                        ContentUnavailableView("Order access unavailable", systemImage: "lock",
                                               description: Text("This login cannot read customer orders."))
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                if let group = vm.detail?.requestedGroup {
                    CustomerGroupRequestBanner(vm: vm, groupName: group, onSaved: onSaved)
                }
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        sectionPicker.pickerStyle(.menu)
                    } else {
                        sectionPicker.pickerStyle(.segmented).labelsHidden()
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 340)
                .padding(.vertical, 12)
                .padding(.horizontal)
                Divider()
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity)
        }
        .sheet(isPresented: $creatingOrder, onDismiss: { vm.orders?.reload() }) {
            if let detail = vm.detail {
                CustomerOrderCreateSheet(api: vm.api, shop: vm.shop, customer: detail) { id in
                    createdOrderId = id
                    Task { await vm.load(); onSaved() }
                }
            }
        }
        .navigationDestination(item: $createdOrderId) { OrderDetailView(shop: vm.shop, orderId: $0) }
    }

    private var sectionPicker: some View {
        Picker("Customer section", selection: $tab) {
            ForEach(CustomerDetailTab.allCases) { Text($0.title).tag($0) }
        }
    }
}
