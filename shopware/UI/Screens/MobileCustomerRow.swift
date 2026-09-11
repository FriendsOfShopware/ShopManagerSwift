#if os(iOS)
import SwiftUI

struct MobileCustomerRow: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    let shop: ConnectedShop
    let customer: CustomerRow

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(customer.name).font(.headline)
            if !customer.email.isEmpty { Text(customer.email).foregroundStyle(.secondary) }
            if !customer.company.isEmpty { Text(customer.company).foregroundStyle(.secondary) }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { metadata }
                VStack(alignment: .leading, spacing: 4) { metadata }
            }.font(.subheadline).foregroundStyle(.secondary)
            if !customer.active { Text("Inactive customer").font(.subheadline).foregroundStyle(.secondary) }
            if customer.guest { Text("Guest customer").font(.subheadline).foregroundStyle(.secondary) }
            if let group = customer.requestedGroup {
                Label("Requested: \(group)", systemImage: "clock").font(.subheadline).foregroundStyle(.secondary)
            }
            if sizeClass == .regular {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 16) { statistics }
                    VStack(alignment: .leading, spacing: 4) { statistics }
                }.font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var metadata: some View {
        if !customer.customerNumber.isEmpty { Text(customer.customerNumber) }
        if !customer.group.isEmpty { Text(customer.group) }
        if !customer.city.isEmpty { Text(customer.city) }
    }

    @ViewBuilder private var statistics: some View {
        Text("^[\(customer.orderCount) order](inflect: true)")
        Text(shop.fmt(customer.totalSpend))
        if customer.createdAt != .distantPast {
            Text(customer.createdAt, format: .dateTime.day().month().year())
        }
    }
}
#endif
