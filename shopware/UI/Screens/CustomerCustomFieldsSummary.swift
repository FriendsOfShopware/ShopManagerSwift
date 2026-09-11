import SwiftUI
import ShopwareAdminAPI

struct CustomerCustomFieldsSummary: View {
    let sets: [CustomerCustomFieldSet]
    let values: [String: JSONValue]
    let api: ShopApi

    var body: some View {
        ForEach(sets) { set in
            GroupBox(set.label) {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(set.fields) { field in
                        if let entity = field.entity ?? (field.type == "media" ? "media" : nil) {
                            CustomerEntityField(label: field.label, entity: entity, multiple: field.multiple, api: api,
                                                value: .constant(values[field.name]), editable: false, labelProperty: field.config["labelProperty"]?.stringValue)
                        } else {
                            #if os(macOS) || os(iOS)
                            if field.type == "html", let html = values[field.name]?.stringValue {
                                VStack(alignment: .leading) {
                                    Text(field.label).font(.headline)
                                    Text(customerAttributedHTML(html))
                                }
                            } else {
                                LabeledContent(field.label, value: display(values[field.name], field: field))
                            }
                            #else
                            LabeledContent(field.label, value: display(values[field.name], field: field))
                            #endif
                        }
                    }
                }.padding(8).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func display(_ value: JSONValue?, field: CustomerCustomField) -> String {
        guard let value else { return "—" }
        switch value {
        case .null: return "—"
        case let .bool(flag): return String(localized: flag ? "Yes" : "No")
        case let .string(text): return field.options.first { $0.id == text }?.name ?? text
        case let .number(number): return number.formatted()
        case let .array(values): return values.map { display($0, field: field) }.joined(separator: ", ")
        case .object: return String(decoding: value.encoded(sortedKeys: true), as: UTF8.self)
        }
    }
}
