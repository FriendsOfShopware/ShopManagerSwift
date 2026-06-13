import Foundation
import ShopwareAdminAPI

/// Shared by the snapshot (ShopwareDataSource) and the live promotions listing.
func promoCriteria() -> Criteria {
    Criteria()
        .addSorting("createdAt", "DESC")
        .addAssociation("discounts")
        .addIncludes(
            "promotion",
            [
                "id", "name", "active", "validFrom", "validUntil",
                "orderCount", "discounts", "translated", "useIndividualCodes",
            ]
        )
        .addIncludes("promotion_discount", ["type", "value"])
}

func parsePromo(_ p: SwEntity, _ now: Date, _ shop: ConnectedShop) -> ShopPromo {
    let active = p.boolean("active") == true
    let from = p.date("validFrom")
    let until = p.date("validUntil")
    let status: PromoStatus
    if active, let from, from > now {
        status = .scheduled
    } else if active, until == nil || (until.map { $0 > now } ?? false) {
        status = .active
    } else {
        status = .ended
    }
    let window: String
    switch status {
    case .scheduled:
        window = "Starts \(fmtPromoDate(from!))"
    case .active:
        window = until.map { "Ends \(fmtPromoDate($0))" } ?? "No end date"
    case .ended:
        window = until.map { "Ended \(fmtPromoDate($0))" } ?? "Inactive"
    }
    let discount = p.entities("discounts").first
    let detail: String
    switch discount?.string("type") {
    case "percentage":
        detail = "−\(Int(discount?.double("value") ?? 0.0))%"
    case "absolute":
        detail = "−\(shop.fmt(discount?.double("value") ?? 0.0))"
    default:
        detail = "Promotion"
    }
    return ShopPromo(
        name: p.translated("name") ?? "Promotion",
        detail: detail,
        status: status,
        window: window,
        redemptions: p.int("orderCount") ?? 0,
        id: p.id ?? "",
        active: active,
        useIndividualCodes: p.boolean("useIndividualCodes") == true
    )
}

/// Formats a date as e.g. "Jun 5" — abbreviated month + day, in UTC/English (mirrors the
/// Android `DateTimeFormatter.ofPattern("MMM d", Locale.ENGLISH).withZone(ZoneOffset.UTC)`).
private func fmtPromoDate(_ d: Date) -> String {
    var style = Date.FormatStyle.dateTime.month(.abbreviated).day().locale(Locale(identifier: "en_US"))
    style.timeZone = TimeZone(identifier: "UTC")!
    return d.formatted(style)
}
