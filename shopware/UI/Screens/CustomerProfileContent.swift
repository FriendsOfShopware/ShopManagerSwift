import SwiftUI
import ShopwareAdminAPI

struct CustomerProfileContent: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let shop: ConnectedShop
    let detail: CustomerDetail
    let orderTotalCount: Int?
    let api: ShopApi
    var customFieldSets: [CustomerCustomFieldSet] = []
    let onManageAddresses: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                activitySummary
                Divider()
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 40) {
                        account.frame(minWidth: 330, maxWidth: .infinity)
                        activity.frame(minWidth: 330, maxWidth: .infinity)
                    }
                    VStack(alignment: .leading, spacing: 28) {
                        account
                        Divider()
                        activity
                    }
                }
                Divider()
                addresses
                if !detail.tags.isEmpty {
                    Divider()
                    CustomerInfoCard(title: "Tags") {
                        Text(detail.tags.map(\.name).joined(separator: ", "))
                    }
                }
                if !populatedCustomFieldSets.isEmpty {
                    Divider()
                    DisclosureGroup("Additional information") {
                        CustomerCustomFieldsSummary(sets: populatedCustomFieldSets, values: detail.customFields, api: api)
                            .padding(.top, 12)
                    }
                }
            }
            .labeledContentStyle(CustomerProfileLabeledContentStyle())
            .frame(maxWidth: 920, alignment: .leading)
            #if os(macOS)
            .padding(32)
            #else
            .padding(20)
            #endif
            .frame(maxWidth: .infinity)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                if !dynamicTypeSize.isAccessibilitySize {
                    Image(systemName: "person.crop.circle.fill")
                        .font(.largeTitle)
                        .foregroundStyle(.tertiary)
                        .accessibilityHidden(true)
                }
                Text(detail.name)
                    #if os(macOS)
                    .font(.largeTitle)
                    #else
                    .font(.title2)
                    #endif
                    .bold().textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let company = detail.company, !company.isEmpty {
                Text(company).foregroundStyle(.secondary)
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { accountStatus }
                VStack(alignment: .leading, spacing: 8) { accountStatus }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 20) { contactLinks }
                VStack(alignment: .leading, spacing: 8) { contactLinks }
            }.padding(.top, 4)
        }
    }

    @ViewBuilder private var accountStatus: some View {
                    StatusBadge(label: String(localized: detail.active ? "Active" : "Disabled"), tone: detail.active ? .done : .error)
                    Text(detail.guest ? "Guest customer" : "Registered customer").foregroundStyle(.secondary)
    }

    @ViewBuilder private var contactLinks: some View {
        if !detail.email.isEmpty, let url = URL(string: "mailto:\(detail.email)") {
            Link(destination: url) { Label(detail.email, systemImage: "envelope") }
                .textSelection(.enabled)
        }
        if let phone = detail.phone, let url = phoneURL(phone) {
            Link(destination: url) { Label(phone, systemImage: "phone") }
        }
    }

    @ViewBuilder private var activitySummary: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 16) { metrics }
        } else {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 24) { metrics }.fixedSize(horizontal: true, vertical: false)
                VStack(alignment: .leading, spacing: 16) { metrics }
            }.padding(.vertical, 4)
        }
    }

    @ViewBuilder private var metrics: some View {
            CustomerMetricCard(title: "Orders", value: orderTotalCount.map(String.init) ?? "—")
            CustomerMetricCard(title: "Total spend", value: shop.fmt(detail.totalSpend))
            CustomerMetricCard(title: "Last order", value: detail.lastOrderMs.map { relativeAgoText($0) } ?? String(localized: "No orders yet"))
    }

    private var account: some View {
        CustomerInfoCard(title: "Account") {
            LabeledContent("Customer number", value: detail.customerNumber.isEmpty ? "—" : detail.customerNumber)
            LabeledContent("Customer group", value: detail.group ?? "—")
            LabeledContent("Account type", value: String(localized: detail.accountType == "business" ? "Business" : "Private"))
            if detail.accountType == "business" {
                LabeledContent("VAT IDs", value: detail.vatIds.isEmpty ? "—" : detail.vatIds.joined(separator: ", "))
            }
            LabeledContent("Language", value: detail.language)
            if let birthday = detail.birthday,
               let date = SwEntity(.object(["birthday": .string(birthday)])).date("birthday") {
                LabeledContent("Birthday", value: date.formatted(Date.FormatStyle(date: .long, time: .omitted, timeZone: .gmt)))
            }
            if detail.doubleOptInRegistration {
                LabeledContent("Email confirmed", value: String(localized: detail.doubleOptInConfirmDate == nil ? "No" : "Yes"))
            }
        }
    }

    private var activity: some View {
        CustomerInfoCard(title: "Registration & activity") {
            LabeledContent("Customer since", value: detail.customerSince ?? "—")
            LabeledContent("Registered via", value: detail.salesChannel)
            LabeledContent("Login access", value: detail.boundSalesChannel ?? String(localized: "All sales channels"))
            LabeledContent("Last login", value: detail.lastLogin?.formatted(date: .abbreviated, time: .shortened) ?? String(localized: "Never"))
            if let affiliate = detail.affiliateCode, !affiliate.isEmpty { LabeledContent("Affiliate code", value: affiliate) }
            if let campaign = detail.campaignCode, !campaign.isEmpty { LabeledContent("Campaign code", value: campaign) }
            if detail.createdByAdmin { Label("Created by an administrator", systemImage: "person.badge.key").foregroundStyle(.secondary) }
        }
    }

    private var addresses: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Addresses").font(.headline)
                Spacer()
                Button("Manage addresses", action: onManageAddresses)
                    #if os(macOS)
                    .buttonStyle(.link)
                    #else
                    .frame(minHeight: 44)
                    #endif
            }
            if detail.sharedAddress, let billing = detail.billingAddress {
                address(billing, title: "Billing & shipping")
            } else {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: 40) {
                        address(detail.billingAddress, title: "Billing").frame(minWidth: 330, maxWidth: .infinity, alignment: .leading)
                        address(detail.shippingAddress, title: "Shipping").frame(minWidth: 330, maxWidth: .infinity, alignment: .leading)
                    }
                    VStack(alignment: .leading, spacing: 20) {
                        address(detail.billingAddress, title: "Billing")
                        address(detail.shippingAddress, title: "Shipping")
                    }
                }
            }
        }
    }

    private func address(_ value: String?, title: LocalizedStringKey) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).foregroundStyle(.secondary)
            Text(value ?? String(localized: "No address set")).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
        }
    }

    private var populatedCustomFieldSets: [CustomerCustomFieldSet] {
        customFieldSets.filter { set in
            set.fields.contains { field in
                guard let value = detail.customFields[field.name] else { return false }
                return value != .null && value != .string("") && value != .array([])
            }
        }
    }

    private func phoneURL(_ phone: String) -> URL? {
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        return digits.isEmpty ? nil : URL(string: "tel:\(digits)")
    }
}
