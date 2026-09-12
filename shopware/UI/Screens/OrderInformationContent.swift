import SwiftUI
import ShopwareAdminAPI

struct OrderInformationContent: View {
    @Bindable var vm: OrderDetailViewModel
    let detail: OrderDetail
    let transition: (TransitionContext) -> Void
    let tracking: (OrderDelivery) -> Void
    let note: () -> Void
    let edit: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        OrderPage {
            LazyVGrid(columns: typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 400), alignment: .top)], alignment: .leading, spacing: 24) {
            ForEach(detail.payments) { payment in
                OrderCard(title: "Payment", icon: "creditcard") {
                    LabeledContent("Payment method", value: payment.method)
                    LabeledContent("Amount", value: vm.shop.fmt(payment.amount, iso: detail.currencyIso))
                    if !payment.primary { Text("Previous payment attempt").font(.callout).foregroundStyle(.secondary) }
                    OrderStateControl(state: payment.state, canEdit: vm.canTransition(payment.state), transition: transition) { Task { await vm.load() } }
                }
            }
            OrderCard(title: "Billing address", icon: "person.text.rectangle") {
                Text(detail.billing?.formatted ?? String(localized: "No billing address")).textSelection(.enabled)
                if let phone = detail.billing?.phoneNumber, !phone.isEmpty { LabeledContent("Phone", value: phone) }
                Button("Edit order address…", systemImage: "pencil", action: edit).disabled(!vm.canEdit || !vm.permissions.allows("order_address:update"))
            }
            ForEach(detail.deliveries) { delivery in
                OrderCard(title: "Delivery", icon: "shippingbox") {
                    LabeledContent("Shipping method", value: delivery.method)
                    if let address = delivery.address { Text(address.formatted).textSelection(.enabled) }
                    if let earliest = delivery.shippingDateEarliest {
                        LabeledContent { Text(earliest, format: .dateTime.day().month().year()) } label: { Text("Earliest delivery") }
                    }
                    if let latest = delivery.shippingDateLatest {
                        LabeledContent { Text(latest, format: .dateTime.day().month().year()) } label: { Text("Latest delivery") }
                    }
                    OrderStateControl(state: delivery.state, canEdit: vm.canTransition(delivery.state), transition: transition) { Task { await vm.load() } }
                    Divider()
                    Text("Tracking").font(.headline)
                    if delivery.trackingCodes.isEmpty { Text("No tracking codes").foregroundStyle(.secondary) }
                    ForEach(Array(Set(delivery.trackingCodes)).sorted(), id: \.self) { code in
                        if let url = trackingURL(delivery, code: code) { Link(destination: url) { Label(code, systemImage: "arrow.up.right.square") } }
                        else { Text(code).textSelection(.enabled) }
                    }
                    Button("Edit tracking codes…", systemImage: "pencil") { tracking(delivery) }
                        .disabled(!vm.canEdit || !vm.permissions.allows("order_delivery:update"))
                        .accessibilityIdentifier("order.tracking.\(delivery.id)")
                }
            }
            OrderCard(title: "Order information", icon: "info.circle") {
                property("Email", detail.customerEmail)
                property("Sales channel", detail.salesChannel)
                property("Language", detail.language)
                property("Affiliate code", detail.affiliateCode)
                property("Campaign code", detail.campaignCode)
                if !detail.tags.isEmpty { property("Tags", detail.tags.map(\.name).joined(separator: ", ")) }
            }
            OrderCard(title: "Notes", icon: "note.text") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Customer note").font(.headline)
                    Text(detail.customerComment?.isEmpty == false ? detail.customerComment! : String(localized: "Not set")).textSelection(.enabled)
                }
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    Text("Internal note").font(.headline)
                    Text(detail.internalComment?.isEmpty == false ? detail.internalComment! : String(localized: "Not set")).textSelection(.enabled)
                }
                Button("Edit note…", systemImage: "pencil", action: note).disabled(!vm.canEdit).accessibilityIdentifier("order.note.edit")
            }
            }
            if let error = vm.customFieldsError { OrderErrorBanner(message: error) { Task { await vm.loadCustomFields() } } }
            CustomerCustomFieldsSummary(sets: vm.customFieldSets, values: detail.customFields, api: vm.api)
        }.refreshable { await vm.load() }.accessibilityIdentifier("order.details")
    }

    @ViewBuilder private func property(_ title: LocalizedStringKey, _ value: String) -> some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 4) { Text(title).fontWeight(.medium); Text(value.isEmpty ? "—" : value).foregroundStyle(.secondary) }
        } else { LabeledContent(title, value: value.isEmpty ? "—" : value) }
    }

    private func trackingURL(_ delivery: OrderDelivery, code: String) -> URL? {
        guard let template = delivery.trackingURL, !template.isEmpty else { return nil }
        let encoded = code.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        let link = template.replacingOccurrences(of: "%s", with: encoded)
        guard let url = URL(string: link), ["https", "http"].contains(url.scheme?.lowercased() ?? "") else { return nil }
        return url
    }
}

struct OrderActivityContent: View {
    @Bindable var vm: OrderDetailViewModel
    var body: some View {
        Group {
            if vm.timelineLoading && vm.timeline.isEmpty { ProgressView("Loading activity…") }
            else if let error = vm.timelineError {
                ContentUnavailableView {
                    Label("Couldn't load activity", systemImage: "exclamationmark.triangle")
                } description: { Text(error) } actions: { Button("Retry") { Task { await vm.loadTimeline() } } }
            } else if !vm.permissions.allows("state_machine_history:read") {
                ContentUnavailableView("Activity access unavailable", systemImage: "lock", description: Text("This login cannot read order activity."))
            } else if vm.timeline.isEmpty {
                ContentUnavailableView("No activity yet", systemImage: "clock", description: Text("Order, payment, and delivery status changes will appear here."))
            } else {
                List(vm.timeline.reversed()) { entry in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: entry.entity == "order_transaction" ? "creditcard" : entry.entity == "order_delivery" ? "shippingbox" : "doc.text")
                            .foregroundStyle(.secondary).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(entry.entity == "order_transaction" ? "Payment" : entry.entity == "order_delivery" ? "Delivery" : "Order").font(.caption).foregroundStyle(.secondary)
                            Text(entry.toStateName).fontWeight(.semibold)
                            if let from = entry.fromStateName { Text("From \(from)").foregroundStyle(.secondary) }
                            Text(Date(timeIntervalSince1970: Double(entry.createdAtMs) / 1000), format: .dateTime.day().month().year().hour().minute())
                                .font(.callout).foregroundStyle(.secondary)
                            Text(entry.userLabel ?? String(localized: "Automatic")).font(.callout).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 6).accessibilityElement(children: .contain)
                        .accessibilityIdentifier("order.activity.\(entry.id)")
                }.refreshable { await vm.loadTimeline() }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).accessibilityIdentifier("order.activity")
    }
}
