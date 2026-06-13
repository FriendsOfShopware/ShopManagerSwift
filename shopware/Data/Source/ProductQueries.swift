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
                    ["id", "name", "translated", "stock", "active", "parentId", "price", "prices", "productNumber"]
                )
                .addAssociation("prices")
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
            priceEditable: firstPrice != nil && !hasAdvancedPrices && !isVariantChild,
            rawPrice: priceArray(product)
        )
    }

    func saveProductQuickEdit(_ info: ProductQuickInfo, stock: Int, active: Bool, newGross: Double?) async throws {
        var payload: [String: JSONValue] = ["stock": .int(stock), "active": .bool(active)]
        if let scaled = scaledPrice(editable: info.priceEditable, rawPrice: info.rawPrice, oldGross: info.grossPrice, newGross: newGross) {
            payload["price"] = scaled
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
                        "childCount", "releaseDate",
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
            priceEditable: firstPrice != nil && !hasAdvancedPrices,
            rawPrice: priceArray(p),
            taxRate: p.entity("tax")?.double("taxRate"),
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

    func fetchProductVariants(_ parentId: String) async throws -> [ProductVariant] {
        let children = try await repository("product").search(
            Criteria()
                .setLimit(100)
                .addFilter(Criteria.equals("parentId", .string(parentId)))
                .addSorting("productNumber")
                .addAssociation("options.group")
                .addAssociation("prices")
                .addIncludes(
                    "product",
                    ["id", "productNumber", "stock", "active", "price", "prices", "options"]
                )
                .addIncludes("property_group_option", ["name", "translated", "groupId"])
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
                priceEditable: firstPrice != nil && !hasAdvancedPrices,
                rawPrice: priceArray(c)
            )
        }
    }

    // MARK: - Product detail (write)

    /// Patch the base data the detail edit sheet exposes. Price scales every currency entry
    /// by the same factor (same approach as the quick-edit sheet).
    func saveProductDetail(
        _ detail: ProductDetail,
        name: String,
        description: String?,
        active: Bool,
        stock: Int,
        newGross: Double?
    ) async throws {
        var payload: [String: JSONValue] = [
            "name": .string(name),
            "description": nullableField(description),
            "active": .bool(active),
            "stock": .int(stock),
        ]
        if let scaled = scaledPrice(editable: detail.priceEditable, rawPrice: detail.rawPrice, oldGross: detail.grossPrice, newGross: newGross) {
            payload["price"] = scaled
        }
        try await repository("product").patch(detail.id, .object(payload))
    }

    /// Patch a single variant's stock and (optionally) price.
    func saveVariantEdit(_ variant: ProductVariant, stock: Int, newGross: Double?) async throws {
        var payload: [String: JSONValue] = ["stock": .int(stock)]
        if let scaled = scaledPrice(editable: variant.priceEditable, rawPrice: variant.rawPrice, oldGross: variant.grossPrice, newGross: newGross) {
            payload["price"] = scaled
        }
        try await repository("product").patch(variant.id, .object(payload))
    }
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
