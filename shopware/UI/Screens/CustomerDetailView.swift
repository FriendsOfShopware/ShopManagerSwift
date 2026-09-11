import SwiftUI
import ShopwareAdminAPI

struct CustomerDetailView: View {
    @Environment(AppViewModel.self) private var model
    let shop: ConnectedShop
    let customerId: String

    @State private var vm: CustomerDetailViewModel?
    @State private var showingEdit = false
    var onSaved: () -> Void = {}

    var body: some View {
        Group {
            if let vm, vm.detail != nil {
                CustomerWorkspace(vm: vm, onSaved: onSaved)
            } else if let vm, let error = vm.error {
                ContentUnavailableView {
                    Label("Couldn't load customer", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(error)
                } actions: {
                    Button("Retry") { Task { await vm.load() } }
                }
            } else {
                ProgressView()
            }
        }
        .navigationTitle(vm?.detail?.name ?? String(localized: "Customer"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            if vm?.detail != nil {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit customer", systemImage: "pencil") { showingEdit = true }
                        .disabled(vm?.permissions.allows("customer:update") != true || vm?.busy == true)
                        .help("Edit customer contact details and addresses")
                }
                ToolbarItem(placement: .automatic) {
                    Button("Refresh customer", systemImage: "arrow.clockwise") { Task { await vm?.load() } }
                        .disabled(vm?.loading == true || vm?.busy == true)
                }
                if let vm {
                    ToolbarItem(placement: .primaryAction) { CustomerActionsMenu(vm: vm, onSaved: onSaved) }
                }
            }
        }
        .sheet(isPresented: $showingEdit) {
            if let detail = vm?.detail {
                CustomerEditSheet(shop: shop, detail: detail, permissions: vm?.permissions ?? AdminPermissions()) {
                    onSaved()
                    Task { await vm?.load() }
                }
            }
        }
        .alert("Customer action failed", isPresented: Binding(
            get: { vm?.actionError != nil }, set: { if !$0 { vm?.actionError = nil } }
        )) {} message: { Text(vm?.actionError ?? "") }
        .task {
            if vm == nil { vm = CustomerDetailViewModel(repo: model.repo, shop: shop, customerId: customerId) }
            await vm?.load()
        }
    }

}
