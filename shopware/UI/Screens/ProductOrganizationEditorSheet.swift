import SwiftUI
import ShopwareAdminAPI

struct ProductOrganizationEditorSheet: View {
    let product: ProductItem
    let actions: ProductActions
    let onSave: () -> Void
    @State private var draft: ProductOrganizationDraft
    @State private var original: ProductOrganizationDraft
    @State private var selecting: ProductOrganizationRelation?
    @State private var channelNames: [String: String]
    init(product: ProductItem, actions: ProductActions, onSave: @escaping () -> Void) {
        self.product = product; self.actions = actions; self.onSave = onSave
        let draft = ProductOrganizationDraft(product)
        _draft = State(initialValue: draft); _original = State(initialValue: draft)
        _channelNames = State(initialValue: Dictionary(product.visibilities.map { ($0.salesChannelID, $0.name) }, uniquingKeysWith: { first, _ in first }))
    }
    var body: some View {
        EntityEditorSheet(title: "Edit assignments", identifier: "product", busy: actions.busy, changed: draft != original,
                          canSave: actions.canEditOrganization && draft != original && !product.isVariant, error: actions.error) {
            let saved = await actions.saveOrganization(product, draft: draft)
            if saved { onSave() }; return saved
        } content: {
            Section("Organization") {
                choice(.categories, count: draft.categories.count)
                choice(.properties, count: draft.properties.count)
                choice(.tags, count: draft.tags.count)
            }
            Section {
                choice(.salesChannels, count: draft.visibilities.count)
                ForEach(draft.visibilities.keys.sorted(), id: \.self) { id in
                    Picker(channelNames[id] ?? id, selection: $draft[visibility: id]) {
                        Text("Direct link only").tag(10)
                        Text("Search and direct link").tag(20)
                        Text("Visible everywhere").tag(30)
                    }.accessibilityIdentifier("product.visibility." + id)
                }
            } header: { Text("Sales channels") } footer: { Text("Assign a sales channel and choose where customers can find this product.") }
        }.onAppear { actions.error = nil }
        .sheet(item: $selecting) { relation in
            CustomerEntitySelectionSheet(api: actions.api, entity: relation.entity, title: String(localized: relation.title), multiple: true,
                                         selected: selected(relation), sortField: "name", criteria: {
                let criteria = Criteria().addSorting("name")
                if relation == .properties { criteria.addAssociation("group") }
                return criteria
            }) { ids in
                switch relation {
                case .categories: draft.categories = ids
                case .properties: draft.properties = ids
                case .tags: draft.tags = ids
                case .salesChannels:
                    draft.visibilities = Dictionary(uniqueKeysWithValues: ids.map { ($0, draft.visibilities[$0] ?? 30) })
                    Task { await loadChannelNames(ids) }
                }
            }
        }
    }
    private func selected(_ relation: ProductOrganizationRelation) -> Set<String> {
        switch relation { case .categories: draft.categories; case .properties: draft.properties; case .tags: draft.tags; case .salesChannels: Set(draft.visibilities.keys) }
    }
    private func choice(_ relation: ProductOrganizationRelation, count: Int) -> some View {
        Button { selecting = relation } label: {
            LabeledContent { Text("\(count) selected").foregroundStyle(.secondary) } label: { Text(relation.title) }
        }.accessibilityIdentifier("product.organization." + relation.rawValue)
    }
    private func loadChannelNames(_ ids: Set<String>) async {
        guard !ids.isEmpty else { return }
        do {
            let channels = try await actions.api.repository("sales-channel").search(Criteria().setIds(ids.sorted()).setLimit(ids.count))
            for channel in channels.data { if let id = channel.id { channelNames[id] = customerEntityLabel(channel) } }
        } catch { actions.error = error.localizedDescription }
    }
}

private enum ProductOrganizationRelation: String, Identifiable {
    case categories, properties, tags, salesChannels
    var id: String { rawValue }
    var title: LocalizedStringResource {
        switch self { case .categories: "Categories"; case .properties: "Properties"; case .tags: "Tags"; case .salesChannels: "Sales channels" }
    }
    var entity: String {
        switch self { case .categories: "category"; case .properties: "property-group-option"; case .tags: "tag"; case .salesChannels: "sales-channel" }
    }
}
