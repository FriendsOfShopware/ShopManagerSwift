import Foundation
import ShopwareAdminAPI

/// Keeps the loaded record for a minimal update payload and tag-link deletion tracking.
struct CustomerDraft {
    let original: CustomerDetail
    var customer: CustomerDetail
    var password = ""
    var passwordConfirmation = ""

    init(_ detail: CustomerDetail) {
        original = detail
        customer = detail
    }

    var validationError: String? {
        if customer.firstName.trimmed.isEmpty || customer.lastName.trimmed.isEmpty {
            return String(localized: "First name and last name are required.")
        }
        let parts = customer.email.trimmed.split(separator: "@", omittingEmptySubsequences: false)
        if parts.count != 2 || parts.contains(where: { $0.isEmpty }) || customer.email.contains(where: \.isWhitespace) {
            return String(localized: "Enter a valid email address.")
        }
        if customer.accountType == "business" && (customer.company ?? "").trimmed.isEmpty {
            return String(localized: "A company is required for a business account.")
        }
        if customer.groupId.isEmpty || customer.languageId.isEmpty {
            return String(localized: "Select a customer group and language.")
        }
        if let birthday = customer.birthday, !birthday.trimmed.isEmpty, !Self.validBirthday(birthday) {
            return String(localized: "Enter the birthday as YYYY-MM-DD.")
        }
        if password != passwordConfirmation { return String(localized: "The passwords do not match.") }
        return nil
    }

    var removedTagIds: [String] {
        let current = Set(customer.tags.map(\.id))
        return original.tags.map(\.id).filter { !current.contains($0) }
    }

    var hasChanges: Bool { (payload.objectValue?.count ?? 0) > 1 || !removedTagIds.isEmpty }

    func tagPermissionError(_ permissions: AdminPermissions) -> String? {
        if !removedTagIds.isEmpty, !permissions.allows("customer_tag:delete") {
            return String(localized: "Your login cannot remove customer tags.")
        }
        let previous = Set(original.tags.map(\.id))
        if customer.tags.contains(where: { !previous.contains($0.id) }), !permissions.allows("customer_tag:create") {
            return String(localized: "Your login cannot assign customer tags.")
        }
        return nil
    }

    static func validBirthday(_ value: String) -> Bool {
        let parts = value.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              let year = Int(parts[0]), let month = Int(parts[1]), let day = Int(parts[2]), year > 0 else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = DateComponents(year: year, month: month, day: day)
        guard let date = calendar.date(from: components) else { return false }
        return calendar.dateComponents([.year, .month, .day], from: date) == components
    }

    var payload: JSONValue {
        let before = fields(original)
        let after = fields(customer)
        var changes = after.filter { before[$0.key] != $0.value }
        if changes["customFields"] != nil {
            changes["customFields"] = .object(customer.customFields.filter { original.customFields[$0.key] != $0.value })
        }
        changes["id"] = .string(customer.id)
        if !password.isEmpty, !customer.guest { changes["password"] = .string(password) }
        return .object(changes)
    }

    func fields(_ value: CustomerDetail) -> [String: JSONValue] {
        [
            "firstName": .string(value.firstName.trimmed), "lastName": .string(value.lastName.trimmed),
            "email": .string(value.email.trimmed), "salutationId": nullableField(value.salutationId),
            "title": nullableField(value.title), "company": nullableField(value.company),
            "accountType": .string(value.accountType), "vatIds": .array(value.accountType == "business" ? value.vatIds.map { .string($0) } : []),
            "groupId": .string(value.groupId), "active": .bool(value.active), "languageId": .string(value.languageId),
            "birthday": nullableField(value.birthday), "affiliateCode": nullableField(value.affiliateCode),
            "campaignCode": nullableField(value.campaignCode),
            "doubleOptInConfirmDate": value.doubleOptInConfirmDate.map { .string($0.ISO8601Format()) } ?? .null,
            "tags": .array(value.tags.sorted { $0.id < $1.id }.map { .object(["id": .string($0.id)]) }),
            "customFields": .object(value.customFields),
        ]
    }
}
