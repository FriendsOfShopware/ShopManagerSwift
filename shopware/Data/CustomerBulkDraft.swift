import Foundation
import ShopwareAdminAPI

struct CustomerBulkDraft {
    var groupId = ""
    var active: Bool?
    var languageId = ""
    var tagMode = "unchanged"
    var tagIds = Set<String>()
    var customFields: [String: JSONValue] = [:]
    var groupDecision: Bool?

    var hasChanges: Bool {
        !groupId.isEmpty || active != nil || !languageId.isEmpty || tagMode != "unchanged" || !customFields.isEmpty || groupDecision != nil
    }

    func changes(for customer: SwEntity) -> (payload: JSONValue, removedTags: [String]) {
        var payload: [String: JSONValue] = ["id": .string(customer.id ?? "")]
        if !groupId.isEmpty { payload["groupId"] = .string(groupId) }
        if let active { payload["active"] = .bool(active) }
        if !languageId.isEmpty { payload["languageId"] = .string(languageId) }
        if !customFields.isEmpty { payload["customFields"] = .object(customFields) }
        let old = Set(customer.entities("tags").compactMap(\.id))
        let updated: Set<String>
        switch tagMode {
        case "add": updated = old.union(tagIds)
        case "remove": updated = old.subtracting(tagIds)
        case "replace": updated = tagIds
        case "clear": updated = []
        default: updated = old
        }
        if tagMode != "unchanged" {
            payload["tags"] = .array(updated.sorted().map { .object(["id": .string($0)]) })
        }
        return (.object(payload), old.subtracting(updated).sorted())
    }
}
