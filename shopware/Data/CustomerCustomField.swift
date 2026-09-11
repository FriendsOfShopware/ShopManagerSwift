import Foundation
import ShopwareAdminAPI

struct CustomerCustomField: Identifiable {
    let id: String
    let name: String
    let label: String
    let type: String
    let component: String
    let config: JSONValue
    let options: [CustomerOption]
    let entity: String?

    var multiple: Bool { component.contains("multi") }
    var required: Bool { config["required"]?.boolValue ?? false }

    init(_ entity: SwEntity, locale: String) {
        id = entity.id ?? entity.string("name") ?? ""
        name = entity.string("name") ?? ""
        config = entity.json["config"] ?? .object([:])
        label = customFieldLabel(config["label"], locale: locale) ?? name
        type = entity.string("type") ?? "text"
        component = config["componentName"]?.stringValue ?? ""
        self.entity = config["entity"]?.stringValue
        options = (config["options"]?.arrayValue ?? []).compactMap { value in
            guard let id = value["value"]?.stringValue else { return nil }
            return CustomerOption(id: id, name: customFieldLabel(value["label"], locale: locale) ?? id)
        }
    }

    func validationError(_ value: JSONValue?) -> String? {
        if required && (value == nil || value == .null || value == .string("") || value == .array([])) {
            return String(localized: "\(label) is required.")
        }
        if let number = value?.doubleValue {
            if let min = config["min"]?.doubleValue, number < min { return String(localized: "\(label) must be at least \(min).") }
            if let max = config["max"]?.doubleValue, number > max { return String(localized: "\(label) must be at most \(max).") }
        }
        return nil
    }
}

func customFieldLabel(_ value: JSONValue?, locale: String) -> String? {
    if let text = value?.stringValue, !text.isEmpty { return text }
    guard let labels = value?.objectValue else { return nil }
    let language = String(locale.prefix(2))
    return labels[locale]?.stringValue ?? labels["\(language)-\(language.uppercased())"]?.stringValue
        ?? labels["en-GB"]?.stringValue ?? labels["en-US"]?.stringValue
        ?? labels.keys.sorted().compactMap { labels[$0]?.stringValue }.first
}
