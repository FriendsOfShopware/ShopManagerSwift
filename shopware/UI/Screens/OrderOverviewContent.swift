import SwiftUI
import ShopwareAdminAPI

struct OrderOverviewContent: View {
    @Bindable var vm: OrderDetailViewModel
    let detail: OrderDetail
    let transition: (TransitionContext) -> Void
    let edit: () -> Void
    let openCustomer: () -> Void
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var width: CGFloat = 0
    private var wide: Bool { width >= 860 && !typeSize.isAccessibilitySize }

    var body: some View {
        OrderPage {
            header
            let layout = wide ? AnyLayout(HStackLayout(alignment: .top, spacing: 24)) : AnyLayout(VStackLayout(alignment: .leading, spacing: 24))
            layout {
                OrderCard(title: "Items", icon: "shippingbox") {
                    OrderItemsContent(shop: vm.shop, detail: detail)
                    Button("Edit items…", systemImage: "pencil", action: edit).disabled(!vm.canEdit)
                        .accessibilityIdentifier("order.items.edit")
                }.frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 24) {
                    OrderCard(title: "Totals", icon: "sum") { OrderTotalsContent(shop: vm.shop, detail: detail) }
                    OrderCard(title: "Order status", icon: "checkmark.circle") {
                        if let state = detail.states.first(where: { $0.entity == "order" }) {
                            OrderStateControl(state: state, canEdit: vm.canTransition(state), transition: transition) { Task { await vm.load() } }
                        }
                    }
                }.frame(maxWidth: wide ? 300 : .infinity, alignment: .leading)
            }
            if !promotions.isEmpty {
                OrderCard(title: "Promotions", icon: "tag") {
                    ForEach(promotions) { item in
                        LabeledContent(item.label, value: vm.shop.fmt(item.totalPrice, iso: detail.currencyIso))
                        if let code = item.payload["code"]?.stringValue, !code.isEmpty { Text(code).font(.callout).foregroundStyle(.secondary) }
                    }
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .refreshable { await vm.load() }
        .accessibilityIdentifier("order.overview")
    }

    private var promotions: [OrderLineItem] { detail.lineItems.filter { $0.type == "promotion" } }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(detail.customerName).font(.title2.bold()).textSelection(.enabled)
            if !detail.company.isEmpty { Text(detail.company).foregroundStyle(.secondary) }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 16) { headerMetadata }
                VStack(alignment: .leading, spacing: 6) { headerMetadata }
            }.font(.callout).foregroundStyle(.secondary)
            let contactLayout = width < 650 || typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout())
            contactLayout {
                if let url = URL(string: "mailto:" + detail.customerEmail), !detail.customerEmail.isEmpty {
                    Link(destination: url) { Label(detail.customerEmail, systemImage: "envelope") }
                }
                if width >= 650 && !typeSize.isAccessibilitySize { Spacer(minLength: 12) }
                if detail.customerId != nil && vm.permissions.allows("customer:read") {
                    Button("View customer", systemImage: "person.crop.circle", action: openCustomer)
                        .accessibilityIdentifier("order.customer")
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private var headerMetadata: some View {
        if let date = detail.placedAt { Label { Text(date, format: .dateTime.day().month().year().hour().minute()) } icon: { Image(systemName: "calendar") } }
        Label(detail.salesChannel, systemImage: "storefront")
        if !detail.customerNumber.isEmpty { Text(detail.customerNumber) }
    }
}

struct OrderItemsContent: View {
    let shop: ConnectedShop
    let detail: OrderDetail
    @Environment(\.dynamicTypeSize) private var typeSize
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    private var compact: Bool {
        #if os(iOS)
        sizeClass == .compact || typeSize.isAccessibilitySize
        #else
        typeSize.isAccessibilitySize
        #endif
    }

    var body: some View {
        if detail.lineItems.isEmpty { Text("No items").foregroundStyle(.secondary) }
        else if compact {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(orderedItems) { item in
                    VStack(alignment: .leading, spacing: 6) {
                        itemLabel(item)
                        Text("\(item.quantity) × \(shop.fmt(item.unitPrice, iso: detail.currencyIso))").font(.callout).foregroundStyle(.secondary)
                        Text(shop.fmt(item.totalPrice, iso: detail.currencyIso)).fontWeight(.semibold)
                    }.accessibilityElement(children: .combine).accessibilityIdentifier("order.item.\(item.id)")
                    if item.id != orderedItems.last?.id { Divider() }
                }
            }
        } else {
            Grid(alignment: .leading, horizontalSpacing: 20, verticalSpacing: 12) {
                GridRow {
                    Text("Product").frame(maxWidth: .infinity, alignment: .leading)
                    Text("Quantity")
                    Text("Unit price")
                    Text("Total")
                }.font(.caption).foregroundStyle(.secondary)
                Divider().gridCellUnsizedAxes(.horizontal)
                ForEach(orderedItems) { item in
                    GridRow {
                        itemLabel(item).frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityIdentifier("order.item.\(item.id)")
                        Text(item.quantity, format: .number).monospacedDigit()
                        Text(shop.fmt(item.unitPrice, iso: detail.currencyIso)).monospacedDigit()
                        Text(shop.fmt(item.totalPrice, iso: detail.currencyIso)).monospacedDigit().fontWeight(.medium)
                    }
                }
            }.textSelection(.enabled)
        }
    }

    private func itemLabel(_ item: OrderLineItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.label).fontWeight(.medium)
            if let number = item.productNumber, !number.isEmpty { Text(number).font(.caption).foregroundStyle(.secondary) }
            if let parent = detail.lineItems.first(where: { $0.id == item.parentId }) {
                Label(parent.label, systemImage: "arrow.turn.down.right").font(.caption).foregroundStyle(.secondary)
            }
        }.accessibilityElement(children: .combine)
            .accessibilityLabel(Text(verbatim: [item.label, item.productNumber].compactMap { $0 }.joined(separator: ", ")))
    }

    private var orderedItems: [OrderLineItem] {
        var result: [OrderLineItem] = []
        var visited = Set<String>()
        func append(_ item: OrderLineItem) {
            guard visited.insert(item.id).inserted else { return }
            result.append(item)
            for child in detail.lineItems where child.parentId == item.id { append(child) }
        }
        for item in detail.lineItems where item.parentId == nil { append(item) }
        for item in detail.lineItems where !visited.contains(item.id) { append(item) }
        return result
    }
}

struct OrderTotalsContent: View {
    let shop: ConnectedShop
    let detail: OrderDetail
    var body: some View {
        LabeledContent("Subtotal", value: money(detail.positionPrice))
        LabeledContent("Shipping", value: money(detail.shippingTotal))
        if detail.taxStatus != "tax-free" {
            LabeledContent("Net", value: money(detail.netTotal))
            ForEach(detail.taxes) { tax in
                LabeledContent { Text(money(tax.amount)) } label: {
                    Text("Tax \(tax.rate.formatted(.number.precision(.fractionLength(0...3))))%")
                }
            }
        } else { Text("Tax-free order").font(.callout).foregroundStyle(.secondary) }
        if abs(detail.unroundedTotal - detail.amountTotal) > 0.00001 {
            LabeledContent("Rounding", value: money(detail.amountTotal - detail.unroundedTotal))
        }
        Divider()
        LabeledContent("Total", value: money(detail.amountTotal)).font(.headline)
            .accessibilityIdentifier("order.total")
    }
    private func money(_ amount: Double) -> String {
        amount.formatted(.currency(code: detail.currencyIso ?? shop.currency)
            .locale(shop.localeCode.map { Locale(identifier: $0) } ?? .current)
            .precision(.fractionLength(max(0, min(10, detail.currencyDecimals)))))
    }
}
