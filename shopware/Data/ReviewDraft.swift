import Foundation
import ShopwareAdminAPI

struct ReviewDraft: Equatable {
    var approved: Bool
    var languageId: String
    var comment: String
    var customFields: [String: JSONValue]

    init(_ review: ReviewItem) {
        approved = review.approved
        languageId = review.languageId ?? ""
        comment = review.comment
        customFields = review.customFields
    }

    func validationError(sets: [CustomerCustomFieldSet]) -> String? {
        if languageId.isEmpty { return String(localized: "Choose a language for this review.") }
        return sets.flatMap(\.fields).compactMap { $0.validationError(customFields[$0.name]) }.first
    }

    var payload: JSONValue {
        .object(["status": .bool(approved), "languageId": .string(languageId),
                 "comment": .string(comment), "customFields": .object(customFields)])
    }
}
