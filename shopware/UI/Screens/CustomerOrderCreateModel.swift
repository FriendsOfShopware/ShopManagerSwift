import Foundation
import Observation
import ShopwareAdminAPI

@MainActor @Observable
final class CustomerOrderCreateModel {
    let api: ShopApi
    let customer: CustomerDetail
    private(set) var token: String?
    private(set) var cart: CustomerOrderCart?
    private(set) var busy = false
    private(set) var ready = false
    private(set) var error: String?
    private(set) var checkoutUncertain = false
    private(set) var currencyIso = "EUR"
    private(set) var choices: [String: [CustomerOption]] = [:]
    private(set) var contextValues: [String: String] = [:]
    var sendMail = true

    init(api: ShopApi, customer: CustomerDetail) {
        self.api = api
        self.customer = customer
    }

    var canCreate: Bool { ready && !busy && error == nil && !checkoutUncertain && cart?.items.isEmpty == false && cart?.blocksCheckout == false }

    func reloadCart() async {
        await perform { try await self.refresh() }
    }

    func start() async {
        guard !busy, !ready else { return }
        busy = true
        error = nil
        defer { busy = false }
        do {
            let channel = customer.salesChannelId
            guard !channel.isEmpty else { throw ApiError.validation(violations: []) }
            if token == nil {
                let created = try await api.customerOrders.cart(salesChannelId: channel)
                guard let newToken = created["token"]?.stringValue, !newToken.isEmpty else {
                    throw ApiError.unexpected(status: 200, message: String(localized: "Cart response is missing its token."))
                }
                token = newToken
            }
            guard let currentToken = token else { return }
            token = try await api.customerOrders.assignCustomer(customer.id, salesChannelId: channel, token: currentToken)
            for (field, entity) in [("paymentMethodId", "payment-method"), ("shippingMethodId", "shipping-method"), ("currencyId", "currency"), ("languageId", "language")] {
                choices[field] = try await api.customerOptions(entity, criteria: Criteria()
                    .addFilter(Criteria.equals("salesChannels.id", .string(channel))).addSorting("name"))
            }
            choices["billingAddressId"] = try await addressChoices()
            choices["shippingAddressId"] = choices["billingAddressId"]
            try await refresh()
            ready = true
        } catch { self.error = (error as? ApiError)?.message ?? error.localizedDescription }
    }

    private func addressChoices() async throws -> [CustomerOption] {
        var result: [CustomerOption] = []
        var page = 1
        while true {
            let addresses = try await api.repository("customer-address").search(Criteria().setPage(page).setLimit(100).setTotalCountMode(.exact)
                .addFilter(Criteria.equals("customerId", .string(customer.id))).addAssociation("country").addAssociation("countryState")
                .addSorting("lastName").addSorting("id"))
            result += addresses.data.map { CustomerOption(id: $0.id ?? "", name: parseEditableAddress($0).formatted.replacingOccurrences(of: "\n", with: ", ")) }
            if addresses.data.isEmpty || page * 100 >= addresses.total { return result }
            page += 1
        }
    }

    private func refresh() async throws {
        guard let token else { return }
        let context = try await api.customerOrders.context(salesChannelId: customer.salesChannelId, token: token)
        let entity = SwEntity(context)
        currencyIso = entity.entity("currency")?.string("isoCode") ?? currencyIso
        for key in ["paymentMethod", "shippingMethod", "currency"] {
            if let value = entity.entity(key), let id = value.id {
                contextValues[key + "Id"] = id
                if choices[key + "Id"]?.contains(where: { $0.id == id }) != true {
                    choices[key + "Id", default: []].append(CustomerOption(id: id, name: customerEntityLabel(value)))
                }
            }
        }
        contextValues["languageId"] = context["context"]?["languageIdChain"]?.arrayValue?.first?.stringValue ?? customer.languageId
        let assignedCustomer = entity.entity("customer")
        contextValues["billingAddressId"] = assignedCustomer?.entity("activeBillingAddress")?.id ?? assignedCustomer?.string("defaultBillingAddressId")
        contextValues["shippingAddressId"] = assignedCustomer?.entity("activeShippingAddress")?.id ?? assignedCustomer?.string("defaultShippingAddressId")
        cart = CustomerOrderCart(json: try await api.customerOrders.cart(salesChannelId: customer.salesChannelId, token: token))
    }

    func changeContext(field: String, id: String) async {
        await perform {
            guard let token = self.token else { return }
            self.token = try await self.api.customerOrders.updateContext(.object([field: .string(id)]), salesChannelId: self.customer.salesChannelId, token: token)
            try await self.refresh()
        }
    }

    func addProducts(_ ids: Set<String>) async {
        await perform {
            guard let token = self.token else { return }
            let items: [JSONValue] = ids.sorted().map { id in
                .object(["id": .string(id), "referencedId": .string(id), "type": "product", "quantity": .int(1), "stackable": true, "removable": true])
            }
            self.cart = CustomerOrderCart(json: try await self.api.customerOrders.saveItems(items, salesChannelId: self.customer.salesChannelId, token: token))
        }
    }

    func quantity(id: String, amount: Int) async {
        await perform {
            guard let token = self.token else { return }
            self.cart = CustomerOrderCart(json: try await self.api.customerOrders.saveItems([
                .object(["id": .string(id), "quantity": .int(amount)]),
            ], salesChannelId: self.customer.salesChannelId, token: token, updating: true))
        }
    }

    func remove(id: String) async {
        await perform {
            guard let token = self.token else { return }
            self.cart = CustomerOrderCart(json: try await self.api.customerOrders.removeItem(id, salesChannelId: self.customer.salesChannelId, token: token))
        }
    }

    func promotion(code: String) async {
        await perform {
            guard let token = self.token else { return }
            self.cart = CustomerOrderCart(json: try await self.api.customerOrders.saveItems([
                .object(["type": "promotion", "referencedId": .string(code.trimmed)]),
            ], salesChannelId: self.customer.salesChannelId, token: token))
        }
    }

    func create() async -> String? {
        guard canCreate, let token else { return nil }
        busy = true
        error = nil
        defer { busy = false }
        do {
            let id = try await api.customerOrders.checkout(salesChannelId: customer.salesChannelId, token: token, sendMail: sendMail)
            self.token = nil
            ready = false
            return id
        } catch {
            self.error = (error as? ApiError)?.message ?? error.localizedDescription
            switch error as? ApiError {
            case .validation, .forbidden, .auth, .authExpired, .notFound: break
            default:
                checkoutUncertain = true
                self.error = String(localized: "The order result could not be confirmed. Close this window and check the customer's order history before creating another order.")
            }
            return nil
        }
    }

    func cancel() async -> Bool {
        guard !busy else { return false }
        busy = true
        defer { busy = false }
        do {
            if let token, !checkoutUncertain {
                try await api.customerOrders.cancel(salesChannelId: customer.salesChannelId, token: token)
            }
            token = nil
            return true
        } catch {
            self.error = (error as? ApiError)?.message ?? error.localizedDescription
            return false
        }
    }

    private func perform(_ action: () async throws -> Void) async {
        guard ready, !busy, !checkoutUncertain else { return }
        busy = true
        error = nil
        defer { busy = false }
        do { try await action() }
        catch { self.error = (error as? ApiError)?.message ?? error.localizedDescription }
    }
}
