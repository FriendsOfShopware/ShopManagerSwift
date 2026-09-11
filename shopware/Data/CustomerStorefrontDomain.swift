import Foundation
import ShopwareAdminAPI

struct CustomerStorefrontDomain: Identifiable {
    let id: String
    let salesChannelId: String
    let name: String
    let url: URL
}

extension ShopApi {
    func customerStorefrontDomains(boundSalesChannelId: String?) async throws -> [CustomerStorefrontDomain] {
        let criteria = Criteria().setLimit(100).setTotalCountMode(.exact)
            .addAssociation("salesChannel")
            .addFilter(Criteria.equals("salesChannel.active", true))
            .addFilter(Criteria.equals("salesChannel.typeId", "8a243080f92e4c719546314b577cf82b"))
            .addSorting("salesChannel.name").addSorting("id")
        if let boundSalesChannelId { criteria.addFilter(Criteria.equals("salesChannelId", .string(boundSalesChannelId))) }
        var domains: [CustomerStorefrontDomain] = []
        var page = 1
        while true {
            let result = try await repository("sales-channel-domain").search(criteria.setPage(page))
            domains += result.data.compactMap {
                guard let id = $0.id, let channelId = $0.string("salesChannelId"), let rawURL = $0.string("url"),
                      let url = URL(string: rawURL), ["http", "https"].contains(url.scheme ?? "") else { return nil }
                return CustomerStorefrontDomain(id: id, salesChannelId: channelId,
                                                name: $0.entity("salesChannel")?.translated("name") ?? rawURL, url: url)
            }
            if result.data.isEmpty || page * 100 >= result.total { return domains }
            page += 1
        }
    }
}

/// The one-use impersonation token belongs in a POST body, never browser history or a URL.
func customerImitationRequest(domain: URL, token: String, customerId: String, userId: String) -> URLRequest {
    var request = URLRequest(url: domain.appending(path: "account/login/imitate-customer"))
    request.httpMethod = "POST"
    request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
    var allowed = CharacterSet.urlQueryAllowed
    allowed.remove(charactersIn: "&=+?#")
    let fields = [("token", token), ("customerId", customerId), ("userId", userId)]
    request.httpBody = Data(fields.map { key, value in
        "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")"
    }.joined(separator: "&").utf8)
    return request
}
