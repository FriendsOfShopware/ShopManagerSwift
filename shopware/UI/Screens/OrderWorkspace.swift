import SwiftUI
import ShopwareAdminAPI

struct OrderWorkspace: View {
    @Bindable var vm: OrderDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var tab: OrderDetailTab = .overview
    @State private var sheet: OrderDetailSheet?
    @State private var customerID: String?
    @State private var deleting = false

    var body: some View {
        VStack(spacing: 0) {
            if let error = vm.error ?? vm.permissionsError {
                OrderErrorBanner(message: error) { Task { await vm.load() } }
            }
            if let detail = vm.detail {
                Group {
                    switch tab {
                    case .overview:
                        OrderOverviewContent(vm: vm, detail: detail, transition: { sheet = .transition($0) },
                                             edit: { sheet = .edit }, openCustomer: { customerID = detail.customerId })
                    case .details:
                        OrderInformationContent(vm: vm, detail: detail, transition: { sheet = .transition($0) },
                                                tracking: { sheet = .tracking($0) }, note: { sheet = .note }, edit: { sheet = .edit })
                    case .documents: OrderDocumentsContent(vm: vm, detail: detail) { sheet = .document }
                    case .activity: OrderActivityContent(vm: vm)
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                Group {
                    if typeSize.isAccessibilitySize { sectionPicker.pickerStyle(.menu) }
                    else { sectionPicker.pickerStyle(.segmented).labelsHidden() }
                }
                .frame(maxWidth: 440).padding(.horizontal).padding(.vertical, 12)
                Divider()
            }.fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit order", systemImage: "pencil") { sheet = .edit }
                    .disabled(!vm.canEdit || vm.loading).help("Edit order")
                    .accessibilityIdentifier("order.edit")
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Refresh order", systemImage: "arrow.clockwise") { Task { await vm.load() } }
                    .disabled(vm.loading || vm.busy).help("Refresh order")
                    .accessibilityIdentifier("order.refresh")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Generate document…", systemImage: "doc.badge.plus") { sheet = .document }.disabled(!vm.canCreateDocuments)
                    if vm.detail?.customerId != nil {
                        Button("View customer", systemImage: "person.crop.circle") { customerID = vm.detail?.customerId }
                            .disabled(!vm.permissions.allows("customer:read"))
                    }
                    Divider()
                    Button("Delete order…", systemImage: "trash", role: .destructive) { deleting = true }.disabled(!vm.canDelete)
                } label: { Label("Order actions", systemImage: "ellipsis.circle") }
                .accessibilityIdentifier("order.actions")
            }
        }
        .sheet(item: $sheet) { destination in
            Group {
                switch destination {
                case .edit: OrderEditSheet(vm: vm)
                case .transition(let context): TransitionSheet(vm: vm, context: context)
                case .tracking(let delivery): OrderTrackingSheet(vm: vm, delivery: delivery)
                case .note: OrderNoteSheet(vm: vm)
                case .document: OrderDocumentSheet(vm: vm)
                }
            }.dynamicTypeSize(typeSize)
        }
        .navigationDestination(item: $customerID) { CustomerDetailView(shop: vm.shop, customerId: $0) }
        .alert("Delete this order?", isPresented: $deleting) {
            Button("Cancel", role: .cancel) { }
            Button("Delete order", role: .destructive) { Task { if await vm.deleteOrder() { dismiss() } } }
                .accessibilityIdentifier("order.delete.confirm")
        } message: { Text("The order and its related records will be permanently deleted. This cannot be undone.") }
        .alert("Order action failed", isPresented: Binding(get: { vm.actionError != nil && sheet == nil }, set: { if !$0 { vm.actionError = nil } })) {
            Button("OK") { vm.actionError = nil }
        } message: { Text(vm.actionError ?? "") }
        .overlay(alignment: .bottom) {
            if vm.busy { ProgressView("Updating order…").padding().background(.regularMaterial, in: .rect(cornerRadius: 12)).padding() }
        }
    }

    private var sectionPicker: some View {
        Picker("Order section", selection: $tab) {
            ForEach(OrderDetailTab.allCases) { Text($0.title).tag($0).accessibilityIdentifier("order.tab.\($0.rawValue)") }
        }.accessibilityIdentifier("order.sections")
    }
}

enum OrderDetailTab: String, CaseIterable, Identifiable {
    case overview, details, documents, activity
    var id: Self { self }
    var title: LocalizedStringKey {
        switch self { case .overview: "Overview"; case .details: "Details"; case .documents: "Documents"; case .activity: "Activity" }
    }
}

private enum OrderDetailSheet: Identifiable {
    case edit, transition(TransitionContext), tracking(OrderDelivery), note, document
    var id: String {
        switch self {
        case .edit: "edit"
        case .transition(let context): context.id
        case .tracking(let delivery): "tracking-" + delivery.id
        case .note: "note"
        case .document: "document"
        }
    }
}

struct OrderErrorBanner: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        HStack(alignment: .top) {
            Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
            Spacer(minLength: 12)
            Button("Retry", action: retry)
        }.font(.callout).padding().fixedSize(horizontal: false, vertical: true)
    }
}

struct OrderPage<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) { content }
                .frame(maxWidth: 1160, alignment: .leading).padding(24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }
}

struct OrderCard<Content: View>: View {
    let title: LocalizedStringKey
    let icon: String
    @ViewBuilder let content: Content
    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 14) { content }
                .frame(maxWidth: .infinity, alignment: .leading).padding(8)
                .labeledContentStyle(OrderPropertyStyle())
        } label: { Label(title, systemImage: icon) }
    }
}

private struct OrderPropertyStyle: LabeledContentStyle {
    @Environment(\.dynamicTypeSize) private var typeSize
    func makeBody(configuration: Configuration) -> some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 4)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
        layout {
            configuration.label.foregroundStyle(.secondary)
            if !typeSize.isAccessibilitySize { Spacer(minLength: 12) }
            configuration.content.multilineTextAlignment(typeSize.isAccessibilitySize ? .leading : .trailing)
        }
    }
}

struct OrderStateControl: View {
    let state: OrderStateInfo
    let canEdit: Bool
    let transition: (TransitionContext) -> Void
    let retry: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8)) : AnyLayout(HStackLayout())
        layout {
            StatusBadge(label: state.stateName, tone: stateTone(state.stateTechnical))
            if !typeSize.isAccessibilitySize { Spacer() }
            if let error = state.transitionsError, canEdit {
                Button("Reload status actions", systemImage: "arrow.clockwise", action: retry).help(error)
            } else if !state.transitions.isEmpty {
                Menu("Change status") {
                    ForEach(state.transitions, id: \.actionName) { action in
                        Button(action.displayName) { transition(TransitionContext(state: state, transition: action)) }
                            .accessibilityIdentifier("order.transition.\(state.entityId).\(action.actionName)")
                    }
                }.disabled(!canEdit).accessibilityIdentifier("order.state.\(state.entityId)")
            }
        }
    }
}
