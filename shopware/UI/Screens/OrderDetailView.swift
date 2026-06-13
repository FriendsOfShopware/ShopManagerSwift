import SwiftUI
import ShopwareAdminAPI

/// Live order detail: state cards (with rich transition sheet), line items, totals/taxes,
/// addresses, payment/shipping, tracking, documents (generate + share), and the activity timeline.
struct OrderDetailView: View {
    @Environment(AppViewModel.self) private var model
    let shop: ConnectedShop
    let orderId: String

    @State private var vm: OrderDetailViewModel?
    @State private var transitionContext: TransitionContext?
    @State private var sharePayload: SharePayload?

    var body: some View {
        Group {
            if let vm {
                content(vm)
            } else {
                ProgressView()
            }
        }
        .navigationTitle("Order")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task {
            if vm == nil { vm = OrderDetailViewModel(repo: model.repo, shop: shop, orderId: orderId) }
            await vm?.load()
        }
    }

    @ViewBuilder
    private func content(_ vm: OrderDetailViewModel) -> some View {
        if let detail = vm.detail {
            List {
                headerSection(detail)
                stateSection(detail, vm: vm)
                lineItemsSection(detail)
                totalsSection(detail)
                addressSection(detail)
                documentsSection(detail, vm: vm)
                if !vm.timeline.isEmpty { timelineSection(vm.timeline) }
            }
            .overlay { if vm.busyMessage != nil { busyOverlay } }
            .sheet(item: $transitionContext) { ctx in
                TransitionSheet(detail: detail, context: ctx) { sendMail, docIds, comment in
                    Task {
                        await vm.transition(
                            entity: ctx.state.entity, entityId: ctx.state.entityId,
                            actionName: ctx.transition.actionName, sendMail: sendMail,
                            documentIds: docIds, internalComment: comment
                        )
                    }
                }
            }
            .sheet(item: $sharePayload) { payload in
                ShareLink(item: payload.url) { Label("Share", systemImage: "square.and.arrow.up") }
                    .padding()
            }
        } else if let error = vm.error {
            ContentUnavailableView("Couldn't load order", systemImage: "exclamationmark.triangle", description: Text(error))
        } else {
            ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var busyOverlay: some View {
        ZStack {
            Color.black.opacity(0.1).ignoresSafeArea()
            ProgressView().controlSize(.large).padding(24)
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 16))
        }
    }

    // MARK: Header

    private func headerSection(_ detail: OrderDetail) -> some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("#\(detail.orderNumber)").font(.title2.bold())
                Text(detail.orderDateTime).font(.subheadline).foregroundStyle(.secondary)
                Text(detail.customerName).font(.subheadline)
                if !detail.customerEmail.isEmpty {
                    Text(detail.customerEmail).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: State cards

    private func stateSection(_ detail: OrderDetail, vm: OrderDetailViewModel) -> some View {
        Section("Status") {
            ForEach(detail.states) { state in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(state.label).font(.caption).foregroundStyle(.secondary)
                        StatusBadge(label: state.stateName, tone: stateTone(state.stateTechnical))
                    }
                    Spacer()
                    if !state.transitions.isEmpty {
                        Menu("Change") {
                            ForEach(state.transitions, id: \.actionName) { transition in
                                Button(transition.displayName) {
                                    transitionContext = TransitionContext(state: state, transition: transition)
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: Line items

    private func lineItemsSection(_ detail: OrderDetail) -> some View {
        Section("Items") {
            ForEach(detail.lineItems) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.label).font(.subheadline).lineLimit(2)
                        Text("\(item.quantity) × \(shop.fmt(item.unitPrice, iso: detail.currencyIso))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(shop.fmt(item.totalPrice, iso: detail.currencyIso)).font(.subheadline.weight(.medium))
                }
            }
        }
    }

    // MARK: Totals

    private func totalsSection(_ detail: OrderDetail) -> some View {
        Section("Totals") {
            if detail.shippingTotal > 0 {
                totalRow("Shipping", shop.fmt(detail.shippingTotal, iso: detail.currencyIso))
            }
            ForEach(detail.taxes) { tax in
                totalRow("Tax \(Int(tax.rate))%", shop.fmt(tax.amount, iso: detail.currencyIso))
            }
            HStack {
                Text("Total").font(.headline)
                Spacer()
                Text(shop.fmt(detail.amountTotal, iso: detail.currencyIso)).font(.headline)
            }
        }
    }

    private func totalRow(_ label: LocalizedStringKey, _ value: String) -> some View {
        HStack { Text(label).foregroundStyle(.secondary); Spacer(); Text(value) }
            .font(.subheadline)
    }

    // MARK: Addresses + payment/shipping

    @ViewBuilder
    private func addressSection(_ detail: OrderDetail) -> some View {
        Section("Customer & delivery") {
            if let payment = detail.paymentMethod {
                LabeledContent("Payment", value: payment)
            }
            if let shipping = detail.shippingMethod {
                LabeledContent("Shipping", value: shipping)
            }
            if let billing = detail.billingAddress {
                addressBlock("Billing", billing)
            }
            if let shippingAddr = detail.shippingAddress, shippingAddr != detail.billingAddress {
                addressBlock("Shipping address", shippingAddr)
            }
            if !detail.trackingCodes.isEmpty {
                LabeledContent("Tracking", value: detail.trackingCodes.joined(separator: ", "))
            }
        }
    }

    private func addressBlock(_ title: LocalizedStringKey, _ address: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(address).font(.subheadline)
        }
    }

    // MARK: Documents

    private func documentsSection(_ detail: OrderDetail, vm: OrderDetailViewModel) -> some View {
        Section("Documents") {
            ForEach(detail.documents) { doc in
                Button {
                    Task {
                        if let data = await vm.downloadDocument(doc), let url = writeTempPDF(data, name: doc.number) {
                            sharePayload = SharePayload(url: url)
                        }
                    }
                } label: {
                    Label("\(doc.typeName) \(doc.number)", systemImage: "doc.text")
                }
            }
            Menu {
                ForEach(["invoice", "delivery_note", "credit_note", "storno"], id: \.self) { type in
                    Button(documentTypeLabel(type)) { Task { await vm.generateDocument(type: type) } }
                }
            } label: {
                Label("Generate document", systemImage: "plus")
            }
        }
    }

    private func documentTypeLabel(_ type: String) -> LocalizedStringKey {
        switch type {
        case "invoice": "Invoice"
        case "delivery_note": "Delivery note"
        case "credit_note": "Credit note"
        case "storno": "Cancellation"
        default: LocalizedStringKey(type)
        }
    }

    // MARK: Timeline

    private func timelineSection(_ timeline: [OrderTimelineEntry]) -> some View {
        Section("Activity") {
            ForEach(timeline.reversed()) { entry in
                HStack(alignment: .top, spacing: 10) {
                    Circle().fill(stateTone(entry.toStateTechnical).color).frame(width: 8, height: 8).padding(.top, 6)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(entityLabel(entry.entity)) · \(entry.toStateName)").font(.subheadline)
                        Text("\(relativeAgoText(entry.createdAtMs)) · \(entry.userLabel ?? String(localized: "automatic"))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private func entityLabel(_ entity: String) -> String {
        switch entity {
        case "order_transaction": String(localized: "Payment")
        case "order_delivery": String(localized: "Delivery")
        default: String(localized: "Order")
        }
    }

    private func writeTempPDF(_ data: Data, name: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name.isEmpty ? "document" : name).pdf")
        try? data.write(to: url)
        return url
    }
}

/// Identifies which state card + transition the sheet is acting on.
struct TransitionContext: Identifiable {
    let state: OrderStateInfo
    let transition: StateTransition
    var id: String { "\(state.id):\(transition.actionName)" }
}

struct SharePayload: Identifiable {
    let url: URL
    var id: String { url.absoluteString }
}
