import Foundation
import ShopwareAdminAPI

/// Parent products only (variants hidden, as the admin list does); cover + manufacturer for the row.
func productListCriteria() -> Criteria {
    Criteria()
        .addFilter(Criteria.equals("parentId", nil))
        .addSorting("name")
        .addAssociation("cover.media")
        .addAssociation("manufacturer")
        .addIncludes(
            "product",
            ["id", "productNumber", "name", "translated", "active", "stock", "price", "cover", "manufacturer"]
        )
        .addIncludes("product_media", ["media"])
        .addIncludes("media", ["url"])
        .addIncludes("product_manufacturer", ["name", "translated"])
}

func parseProduct(_ p: SwEntity, _ shopBaseUrl: String) -> ProductRow {
    let coverUrl = p.entity("cover")?.entity("media")?.string("url").map { rebaseMediaUrl($0, shopBaseUrl) }
    return ProductRow(
        id: p.id ?? "",
        name: p.translated("name") ?? "—",
        productNumber: p.string("productNumber") ?? "",
        active: p.boolean("active") ?? false,
        stock: p.int("stock") ?? 0,
        grossPrice: firstPriceObject(p)?["gross"]?.doubleValue,
        manufacturer: p.entity("manufacturer")?.translated("name"),
        coverUrl: coverUrl
    )
}

extension ShopApi {
    /// Compact read for the quick-edit sheet: stock/active/price plus the flags that decide price editability.
    func fetchProductQuickInfo(_ productId: String) async throws -> ProductQuickInfo? {
        guard let product = try await repository("product").get(
            productId,
            criteria: Criteria()
                .addIncludes(
                    "product",
                    ["id", "name", "translated", "stock", "active", "parentId", "price", "prices", "productNumber", "tax"]
                )
                .addAssociation("prices")
                .addAssociation("tax")
                .addIncludes("tax", ["taxRate"])
        ) else { return nil }

        let firstPrice = firstPriceObject(product)
        let hasAdvancedPrices = !product.entities("prices").isEmpty
        let isVariantChild = product.string("parentId") != nil

        return ProductQuickInfo(
            id: productId,
            name: product.translated("name") ?? "—",
            productNumber: product.string("productNumber") ?? "",
            stock: product.int("stock") ?? 0,
            active: product.boolean("active") ?? false,
            grossPrice: firstPrice?["gross"]?.doubleValue,
            netPrice: firstPrice?["net"]?.doubleValue,
            priceLinked: firstPrice?["linked"]?.boolValue ?? true,
            taxRate: product.entity("tax")?.double("taxRate"),
            priceEditable: firstPrice != nil && !hasAdvancedPrices && !isVariantChild,
            rawPrice: priceArray(product)
        )
    }

    func saveProductQuickEdit(_ info: ProductQuickInfo, stock: Int, active: Bool, price: PriceEdit?) async throws {
        var payload: [String: JSONValue] = ["stock": .int(stock), "active": .bool(active)]
        if let field = priceField(editable: info.priceEditable, rawPrice: info.rawPrice, price: price) {
            payload["price"] = field
        }
        try await repository("product").patch(info.id, .object(payload))
    }

    // MARK: - Product detail (read)

    func fetchProductDetail(_ productId: String, _ shopBaseUrl: String) async throws -> ProductDetail? {
        guard let p = try await repository("product").get(
            productId,
            criteria: Criteria()
                .addAssociation("manufacturer")
                .addAssociation("tax")
                .addAssociation("cover.media")
                .addAssociation("media.media")
                .addAssociation("categories")
                .addAssociation("prices")
                .addAssociation("visibilities.salesChannel")
                .addIncludes(
                    "product",
                    [
                        "id", "name", "translated", "productNumber", "description", "active",
                        "stock", "availableStock", "price", "prices", "tax", "manufacturer",
                        "cover", "media", "categories", "visibilities", "ratingAverage",
                        "childCount", "releaseDate", "ean", "manufacturerNumber",
                    ]
                )
                .addIncludes("product_manufacturer", ["name", "translated"])
                .addIncludes("tax", ["taxRate", "name"])
                .addIncludes("category", ["name", "translated"])
                .addIncludes("product_media", ["media", "position"])
                .addIncludes("media", ["url"])
                .addIncludes("sales_channel", ["name", "translated"])
                .addIncludes("product_visibility", ["salesChannel"])
        ) else { return nil }

        let firstPrice = firstPriceObject(p)
        let hasAdvancedPrices = !p.entities("prices").isEmpty
        let gallery = p.entities("media")
            .compactMap { $0.entity("media")?.string("url") }
            .map { rebaseMediaUrl($0, shopBaseUrl) }

        return ProductDetail(
            id: productId,
            name: p.translated("name") ?? "—",
            productNumber: p.string("productNumber") ?? "",
            description: p.translated("description")?.nonBlank,
            active: p.boolean("active") ?? false,
            stock: p.int("stock") ?? 0,
            availableStock: p.int("availableStock") ?? 0,
            grossPrice: firstPrice?["gross"]?.doubleValue,
            netPrice: firstPrice?["net"]?.doubleValue,
            priceLinked: firstPrice?["linked"]?.boolValue ?? true,
            priceEditable: firstPrice != nil && !hasAdvancedPrices,
            rawPrice: priceArray(p),
            taxRate: p.entity("tax")?.double("taxRate"),
            ean: p.string("ean")?.nonBlank,
            manufacturerNumber: p.string("manufacturerNumber")?.nonBlank,
            manufacturer: p.entity("manufacturer")?.translated("name"),
            categories: p.entities("categories").compactMap { $0.translated("name") },
            salesChannels: p.entities("visibilities")
                .compactMap { $0.entity("salesChannel")?.translated("name") }
                .distinctOrdered(),
            coverUrl: p.entity("cover")?.entity("media")?.string("url").map { rebaseMediaUrl($0, shopBaseUrl) },
            galleryUrls: gallery,
            ratingAverage: p.double("ratingAverage"),
            childCount: p.int("childCount") ?? 0,
            releaseDateMs: p.date("releaseDate")?.epochMs
        )
    }

    /// `parentTaxRate` is used for variants that inherit the parent's tax (no own tax association).
    func fetchProductVariants(_ parentId: String, parentTaxRate: Double?) async throws -> [ProductVariant] {
        let children = try await repository("product").search(
            Criteria()
                .setLimit(100)
                .addFilter(Criteria.equals("parentId", .string(parentId)))
                .addSorting("productNumber")
                .addAssociation("options.group")
                .addAssociation("prices")
                .addAssociation("tax")
                .addIncludes(
                    "product",
                    ["id", "productNumber", "stock", "active", "price", "prices", "options", "tax"]
                )
                .addIncludes("property_group_option", ["name", "translated", "groupId"])
                .addIncludes("tax", ["taxRate"])
        ).data

        return children.map { c in
            let firstPrice = firstPriceObject(c)
            let hasAdvancedPrices = !c.entities("prices").isEmpty
            return ProductVariant(
                id: c.id ?? "",
                productNumber: c.string("productNumber") ?? "",
                optionLabels: c.entities("options").compactMap { $0.translated("name") },
                active: c.boolean("active") ?? false,
                stock: c.int("stock") ?? 0,
                grossPrice: firstPrice?["gross"]?.doubleValue,
                netPrice: firstPrice?["net"]?.doubleValue,
                priceLinked: firstPrice?["linked"]?.boolValue ?? true,
                taxRate: c.entity("tax")?.double("taxRate") ?? parentTaxRate,
                priceEditable: firstPrice != nil && !hasAdvancedPrices,
                rawPrice: priceArray(c)
            )
        }
    }

    // MARK: - Product detail (write)

    /// Patch the base data the detail edit sheet exposes (name/active/stock/EAN/MPN + gross-net-
    /// linked price). Description is intentionally not editable (rich HTML).
    func saveProductDetail(
        _ detail: ProductDetail,
        name: String,
        active: Bool,
        stock: Int,
        ean: String?,
        manufacturerNumber: String?,
        price: PriceEdit?
    ) async throws {
        var payload: [String: JSONValue] = [
            "name": .string(name),
            "active": .bool(active),
            "stock": .int(stock),
            // null clears a previously-set value; server stores null for an empty string.
            "ean": nullableField(ean),
            "manufacturerNumber": nullableField(manufacturerNumber),
        ]
        if let field = priceField(editable: detail.priceEditable, rawPrice: detail.rawPrice, price: price) {
            payload["price"] = field
        }
        try await repository("product").patch(detail.id, .object(payload))
    }

    /// Patch a single variant's stock and (optionally) gross/net/linked price.
    func saveVariantEdit(_ variant: ProductVariant, stock: Int, price: PriceEdit?) async throws {
        var payload: [String: JSONValue] = ["stock": .int(stock)]
        if let field = priceField(editable: variant.priceEditable, rawPrice: variant.rawPrice, price: price) {
            payload["price"] = field
        }
        try await repository("product").patch(variant.id, .object(payload))
    }
}

/// Emits a "price" JSON array: sets gross/net/linked on the first (default-currency) entry,
/// preserving the rest of that entry's fields and any other currency entries verbatim. Returns nil
/// when not editable or unchanged. The gross/net-verbatim analogue of the old proportional scaler.
func priceField(editable: Bool, rawPrice: JSONValue?, price: PriceEdit?) -> JSONValue? {
    guard let price, editable, case let .array(entries)? = rawPrice, !entries.isEmpty else { return nil }
    let updated = entries.enumerated().compactMap { index, entry -> JSONValue? in
        guard case var .object(o) = entry else { return nil }
        if index == 0 {
            o["gross"] = .number(price.gross)
            o["net"] = .number(price.net)
            o["linked"] = .bool(price.linked)
        }
        return .object(o)
    }
    return .array(updated)
}

private extension String {
    /// The trimmed string, or nil when blank — mirrors Kotlin `takeIf { it.isNotBlank() }`.
    var nonBlank: String? {
        isEmpty || allSatisfy(\.isWhitespace) ? nil : self
    }
}

private extension Array where Element: Equatable {
    /// Order-preserving dedupe, mirroring Kotlin `distinct()`.
    func distinctOrdered() -> [Element] {
        reduce(into: [Element]()) { acc, item in
            if !acc.contains(item) { acc.append(item) }
        }
    }
}
