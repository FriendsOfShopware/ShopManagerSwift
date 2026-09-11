import SwiftUI
import ShopwareAdminAPI

struct CustomerCustomFieldInput: View {
    let field: CustomerCustomField
    let api: ShopApi
    @Binding var value: JSONValue?

    var body: some View {
        if field.config["customFieldType"]?.stringValue == "colorpicker" || field.component.contains("colorpicker") {
            CustomerColorField(label: field.label, value: $value)
        } else if let entity = field.entity ?? (field.type == "media" ? "media" : nil) {
            CustomerEntityField(label: field.label, entity: entity, multiple: field.multiple, api: api, value: $value,
                                labelProperty: field.config["labelProperty"]?.stringValue)
        } else if field.component.contains("select") {
            if field.multiple {
                VStack(alignment: .leading) {
                    Text(field.label).font(.headline)
                    ForEach(field.options) { option in
                        Toggle(option.name, isOn: Binding(
                            get: { value?.arrayValue?.contains(.string(option.id)) == true },
                            set: { selected in
                                var ids = value?.arrayValue ?? []
                                ids.removeAll { $0 == .string(option.id) }
                                if selected { ids.append(.string(option.id)) }
                                value = .array(ids)
                            }
                        ))
                    }
                }
            } else {
                Picker(field.label, selection: text) {
                    Text("Not specified").tag("")
                    ForEach(field.options) { Text($0.name).tag($0.id) }
                }
            }
        } else {
            switch field.type {
            case "json":
                CustomerJSONField(label: field.label, value: $value)
            case "bool":
                Picker(field.label, selection: Binding(
                    get: { value?.boolValue.map { $0 ? "yes" : "no" } ?? "" },
                    set: { value = $0.isEmpty ? .null : .bool($0 == "yes") }
                )) {
                    Text("Not specified").tag("")
                    Text("Yes").tag("yes")
                    Text("No").tag("no")
                }
            case "int":
                TextField(field.label, value: Binding(
                    get: { value?.intValue }, set: { value = $0.map(JSONValue.int) ?? .null }
                ), format: .number)
            case "float":
                TextField(field.label, value: Binding(
                    get: { value?.doubleValue }, set: { value = $0.map(JSONValue.number) ?? .null }
                ), format: .number)
            case "datetime":
                VStack(alignment: .leading) {
                    Toggle(field.label, isOn: Binding(
                        get: { value != nil && value != .null },
                        set: { value = $0 ? .string(Date().ISO8601Format()) : .null }
                    ))
                    if value != nil && value != .null {
                        DatePicker(field.label, selection: Binding(
                            get: { SwEntity(.object(["date": value ?? .null])).date("date") ?? Date() },
                            set: { value = .string($0.ISO8601Format()) }
                        ), displayedComponents: dateComponents)
                        .labelsHidden()
                    }
                }
            #if os(macOS) || os(iOS)
            case "html":
                CustomerRichTextField(label: field.label, value: $value)
            #endif
            default:
                if value?.objectValue != nil || value?.arrayValue != nil {
                    CustomerJSONField(label: field.label, value: $value)
                } else {
                    TextField(field.label, text: text, axis: .vertical).lineLimit(1...6)
                }
            }
        }
    }

    private var text: Binding<String> {
        Binding(get: { value?.stringValue ?? "" }, set: { value = $0.isEmpty ? .null : .string($0) })
    }

    private var dateComponents: DatePickerComponents {
        switch field.config["dateType"]?.stringValue {
        case "date": [.date]
        case "time": [.hourAndMinute]
        default: [.date, .hourAndMinute]
        }
    }
}
