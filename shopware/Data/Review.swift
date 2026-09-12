import Foundation
import ShopwareAdminAPI

/// Review text and rating belong to the customer. Only moderation properties are editable.
struct ReviewItem: Equatable, Identifiable, Sendable {
    var id: String
    var title: String
    var content: String
    var points: Double
    var approved: Bool
    var reviewer: String
    var email: String?
    var customerId: String?
    var productId: String?
    var productName: String
    var salesChannel: String
    var languageId: String?
    var languageName: String
    var createdAt: Date?
    var comment: String
    var customFields: [String: JSONValue]

    var hasReply: Bool { !comment.isEmpty }
    var dateOrder: Double { createdAt?.timeIntervalSince1970 ?? -.infinity }
    var statusOrder: Int { approved ? 1 : 0 }

    init(_ entity: SwEntity) {
        id = entity.id ?? ""
        title = entity.string("title") ?? "—"
        content = entity.string("content") ?? ""
        points = entity.double("points") ?? 0
        approved = entity.boolean("status") ?? false
        let customer = entity.entity("customer")
        let name = [customer?.string("firstName"), customer?.string("lastName")]
            .compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        reviewer = name.isEmpty ? (entity.string("externalUser").flatMap { $0.isEmpty ? nil : $0 } ?? String(localized: "Guest")) : name
        email = customer?.string("email") ?? entity.string("externalEmail")
        customerId = customer?.id
        productId = entity.entity("product")?.id
        productName = entity.entity("product")?.translated("name") ?? "—"
        salesChannel = entity.entity("salesChannel")?.translated("name") ?? "—"
        languageId = entity.string("languageId")
        languageName = entity.entity("language")?.translated("name") ?? "—"
        createdAt = entity.date("createdAt")
        comment = entity.string("comment") ?? ""
        customFields = entity.json["customFields"]?.objectValue ?? [:]
    }
}
