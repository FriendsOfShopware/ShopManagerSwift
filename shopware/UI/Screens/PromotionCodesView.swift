import SwiftUI
import ShopwareAdminAPI

struct PromotionCodesView: View {
    let promotion: PromotionItem
    let actions: PromotionActions
    let revision: Int
    let generate: () -> Void
    @State private var listing: ListingState<PromotionCode>
    @State private var search = ""
    @State private var filter = "all"
    @State private var wide = false
    @Environment(\.dynamicTypeSize) private var typeSize
    init(promotion: PromotionItem, actions: PromotionActions, revision: Int, generate: @escaping () -> Void) {
        self.promotion = promotion; self.actions = actions; self.revision = revision; self.generate = generate
        _listing = State(initialValue: ListingState(filters: [.existence(key: "redeemed", label: String(localized: "Redeemed"), field: "payload", hasLabel: String(localized: "Redeemed"), hasNotLabel: String(localized: "Unused"))], source: { try await actions.api.repository("promotion-individual-code").search($0) },
            baseCriteria: { promotionCodeCriteria(promotion.id) }, mapper: { PromotionCode($0) }))
    }
    var body: some View {
        Group {
            if promotion.codeMode == .automatic {
                ContentUnavailableView("No code required", systemImage: "tag", description: Text("This promotion is applied automatically when its conditions match."))
            } else if promotion.codeMode == .fixed {
                Form {
                    Section("Promotion code") {
                        Text(promotion.code).font(.title2.monospaced()).textSelection(.enabled)
                        ShareLink(item: promotion.code) { Label("Share code", systemImage: "square.and.arrow.up") }
                    }
                }.groupedFormStyle().frame(maxWidth: 920)
            } else if !actions.permissions.allows("promotion_individual_code:read") {
                ContentUnavailableView("Codes unavailable", systemImage: "lock", description: Text("You don't have permission to view individual promotion codes."))
            } else { individualCodes }
        }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onGeometryChange(for: Bool.self) { $0.size.width >= 700 } action: { wide = $0 }
        .task(id: revision) { reload() }
        .task(id: search) {
            do { try await Task.sleep(for: .milliseconds(300)); if listing.term != search { reload() } } catch { }
        }
        .onChange(of: filter) { reload() }
        .onChange(of: actions.permissions) { reload() }
    }
    private var individualCodes: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                ViewThatFits(in: .horizontal) {
                    HStack { codeStatus; Spacer(minLength: 16); generateButton }
                    VStack(alignment: .leading, spacing: 12) { codeStatus; generateButton }
                }
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary).accessibilityHidden(true)
                    TextField("Search codes", text: $search).textFieldStyle(.plain).accessibilityIdentifier("promotion.codes.search")
                    if !search.isEmpty { Button("Clear search", systemImage: "xmark.circle.fill") { search = "" }.labelStyle(.iconOnly).buttonStyle(.plain) }
                }.padding(8).background(.quaternary, in: .rect(cornerRadius: 8))
            }.padding(16).fixedSize(horizontal: false, vertical: true)
            Divider()
            if let error = listing.error { PromotionNotice(message: error) { reload() } }
            Group {
                if listing.loading && listing.items.isEmpty { ProgressView("Loading codes…") }
                else if listing.items.isEmpty {
                    ContentUnavailableView("No matching codes", systemImage: "ticket", description: Text("Generate individual codes or adjust your search."))
                } else if wide && !typeSize.isAccessibilitySize {
                    Table(listing.items) {
                        TableColumn("Code") { Text($0.code).monospaced().textSelection(.enabled) }
                        TableColumn("Status") { status($0) }.width(min: 80, ideal: 110)
                        TableColumn("Customer") { Text($0.customerName ?? "—") }
                        TableColumn("Created") { PromotionDateLabel(date: $0.createdAt) }.width(min: 90, ideal: 120)
                    }
                } else {
                    List(listing.items) { code in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(code.code).font(.headline.monospaced()).textSelection(.enabled)
                            status(code).foregroundStyle(.secondary)
                            if let customer = code.customerName { Text(customer).font(.callout) }
                        }.padding(.vertical, 4)
                    }
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            Divider()
            HStack {
                Text("\(listing.total) codes").foregroundStyle(.secondary)
                Spacer()
                if listing.items.count < listing.total { Button("Load more") { listing.loadMore() }.disabled(listing.loading) }
            }.padding(16).fixedSize(horizontal: false, vertical: true)
        }
    }
    private var codeStatus: some View {
        Picker("Code status", selection: $filter) { Text("All codes").tag("all"); Text("Unused").tag("unused"); Text("Redeemed").tag("redeemed") }
            .accessibilityIdentifier("promotion.codes.filter")
    }
    private var generateButton: some View {
        Button("Generate codes…", systemImage: "plus", action: generate).disabled(!actions.canGenerate).accessibilityIdentifier("promotion.codes.generate")
    }
    private func status(_ code: PromotionCode) -> some View {
        Label(code.redeemed ? "Redeemed" : "Unused", systemImage: code.redeemed ? "checkmark.circle" : "ticket").labelStyle(.titleAndIcon)
    }
    private func reload() {
        guard promotion.codeMode == .individual, actions.permissions.allows("promotion_individual_code:read") else { return }
        listing.setTerm(search)
        listing.applyFilterValues(filter == "all" ? [:] : ["redeemed": .existence(filter == "redeemed")])
    }
}
