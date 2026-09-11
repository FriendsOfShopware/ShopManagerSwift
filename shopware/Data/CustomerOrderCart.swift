import Foundation
import ShopwareAdminAPI

struct CustomerOrderCart {
    let json: JSONValue
    var items: [SwEntity] { SwEntity(json).entities("lineItems") }
    var total: Double { json["price"]?["totalPrice"]?.doubleValue ?? 0 }
    var shipping: Double {
        SwEntity(json).entities("deliveries").reduce(0) { $0 + ($1.json["shippingCosts"]?["totalPrice"]?.doubleValue ?? 0) }
    }
    var messages: [SwEntity] {
        if let errors = json["errors"]?.objectValue { return errors.sorted { $0.key < $1.key }.map { SwEntity($0.value) } }
        return SwEntity(json).entities("errors")
    }
    var blocksCheckout: Bool { messages.contains { $0.boolean("blockOrder") == true } }
}
