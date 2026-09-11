import Foundation
import ShopwareAdminAPI

struct CustomerEditorOptions {
    var salutations: [SalutationOption] = []
    var groups: [CustomerOption] = []
    var languages: [CustomerOption] = []
    var tags: [CustomerOption] = []
    var customFieldSets: [CustomerCustomFieldSet] = []

    static func load(api: ShopApi, customer: CustomerDetail, permissions: AdminPermissions) async throws -> Self {
        async let salutations = api.fetchSalutations()
        async let groups = api.customerOptions("customer-group", criteria: Criteria().addSorting("name"))
        let languageCriteria = Criteria().addSorting("name")
        if !customer.salesChannelId.isEmpty {
            languageCriteria.addFilter(Criteria.equals("salesChannels.id", .string(customer.salesChannelId)))
        }
        async let languages = api.customerOptions("language", criteria: languageCriteria)
        var result = try await Self(salutations: salutations, groups: groups, languages: languages)
        // Available tags are searched in a paged picker instead of loading the entire catalog.
        result.tags = customer.tags
        if permissions.allows("custom_field_set:read") {
            result.customFieldSets = try await api.customerCustomFieldSets(entity: "customer", locale: Locale.current.identifier.replacingOccurrences(of: "_", with: "-"))
        }
        // Keep an existing assignment visible even when it is no longer available for new customers.
        if !result.groups.contains(where: { $0.id == customer.groupId }), !customer.groupId.isEmpty {
            result.groups.append(CustomerOption(id: customer.groupId, name: customer.group ?? customer.groupId))
        }
        if !result.languages.contains(where: { $0.id == customer.languageId }), !customer.languageId.isEmpty {
            result.languages.append(CustomerOption(id: customer.languageId, name: customer.language))
        }
        return result
    }
}
