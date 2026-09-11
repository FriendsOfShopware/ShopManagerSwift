import SwiftUI
import ShopwareAdminAPI

struct CustomerTagsField: View {
    @Binding var tags: [CustomerOption]
    let knownTags: [CustomerOption]
    let api: ShopApi
    let canCreate: Bool
    @State private var addingTag = false

    var body: some View {
        CustomerEntityField(label: String(localized: "Tags"), entity: "tag", multiple: true, api: api, value: Binding(
            get: { .array(tags.map { .string($0.id) }) },
            set: { value in
                tags = (value?.arrayValue ?? []).compactMap(\.stringValue).map { id in
                    tags.first { $0.id == id } ?? knownTags.first { $0.id == id } ?? CustomerOption(id: id, name: id)
                }
            }
        ))
        // The nested sheet keeps the parent save action unavailable until creation finishes.
        .sheet(isPresented: $addingTag) {
            CustomerTagCreateSheet(api: api) { tags.append($0) }
        }
        if canCreate { Button("New tag…", systemImage: "plus") { addingTag = true } }
    }
}
