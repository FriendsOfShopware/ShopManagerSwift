import Foundation
import ShopwareAdminAPI

struct CustomerCustomFieldSet: Identifiable {
    let id: String
    let label: String
    let fields: [CustomerCustomField]
}

extension ShopApi {
    func customerCustomFieldSets(entity: String, locale: String) async throws -> [CustomerCustomFieldSet] {
        let criteria = Criteria().setLimit(100).setTotalCountMode(.exact).addSorting("name")
            .addFilter(Criteria.equals("relations.entityName", .string(entity)))
            .addFilter(Criteria.equals("active", true)).addAssociation("customFields")
        criteria.getAssociation("customFields").addSorting("config.customFieldPosition").addFilter(Criteria.equals("active", true))
        var sets: [CustomerCustomFieldSet] = []
        var page = 1
        while true {
            let result = try await repository("custom-field-set").search(criteria.setPage(page))
            sets += result.data.compactMap { set in
                guard let id = set.id else { return nil }
                return CustomerCustomFieldSet(id: id, label: customFieldLabel(set.json["config"]?["label"], locale: locale) ?? set.string("name") ?? "",
                                              fields: set.entities("customFields").map { CustomerCustomField($0, locale: locale) })
            }
            if result.data.isEmpty || page * 100 >= result.total { return sets }
            page += 1
        }
    }
}
