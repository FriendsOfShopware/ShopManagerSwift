import SwiftUI
import ShopwareAdminAPI

struct CustomerEntityField: View {
    let label: String
    let entity: String
    let multiple: Bool
    let api: ShopApi
    @Binding var value: JSONValue?
    var editable = true
    var labelProperty: String?
    @State private var choosing = false
    @State private var names = ""
    @State private var error: String?

    private var ids: [String] {
        if let values = value?.arrayValue { return values.compactMap(\.stringValue) }
        return value?.stringValue.map { [$0] } ?? []
    }

    var body: some View {
        LabeledContent(label) {
            HStack {
                Text(error ?? (names.isEmpty ? String(localized: "Not specified") : names))
                    .foregroundStyle(.secondary)
                if editable {
                    Button("Choose…") { choosing = true }
                    if !ids.isEmpty { Button("Clear", systemImage: "xmark.circle") { value = .null }.labelStyle(.iconOnly) }
                }
            }
        }
        .task(id: ids) {
            names = ""
            error = nil
            guard !ids.isEmpty else { return }
            do {
                let result = try await api.repository(entity).search(Criteria().setIds(ids).setLimit(ids.count))
                names = result.data.map { customerEntityLabel($0, property: labelProperty) }.joined(separator: ", ")
                if result.data.count != ids.count { error = String(localized: "Some selected items are unavailable") }
            } catch { self.error = String(localized: "Couldn't load selected items") }
        }
        .sheet(isPresented: $choosing) {
            CustomerEntitySelectionSheet(api: api, entity: entity, title: label, multiple: multiple, selected: Set(ids), labelProperty: labelProperty) { ids in
                value = multiple ? .array(ids.sorted().map { .string($0) }) : ids.first.map(JSONValue.string) ?? .null
            }
        }
    }
}

func customerEntityLabel(_ entity: SwEntity, property: String? = nil) -> String {
    if let property, let label = entity.translated(property), !label.isEmpty { return label }
    if let name = entity.translated("name"), !name.isEmpty {
        if let number = entity.string("productNumber") { return "\(name) · \(number)" }
        return name
    }
    let name = [entity.string("firstName"), entity.string("lastName")].compactMap { $0 }.joined(separator: " ")
    if !name.isEmpty { return name }
    return entity.string("fileName") ?? entity.string("label") ?? entity.string("technicalName")
        ?? entity.string("orderNumber") ?? entity.string("productNumber") ?? entity.id ?? String(localized: "Unnamed item")
}
