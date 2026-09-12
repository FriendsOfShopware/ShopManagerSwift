import Foundation

// MARK: - Auth

/// Per-shop persisted auth. Admin holds the AES-GCM-encrypted rotating refresh token,
/// never the password. `password`/`integration` are legacy decode-only variants:
/// password-auth shops migrate themselves on the next grant; integration shops require
/// sign-in-again (support was removed).
nonisolated enum ShopAuth: Codable, Equatable, Sendable {
    /// Admin session: the rotating refresh token is the fast path; `encPassword` (when present)
    /// lets the app silently re-grant if the refresh token is ever revoked, instead of forcing a
    /// sign-in-again. Older files without `encPassword` decode to nil (refresh-token-only).
    case admin(username: String, encRefreshToken: String, encPassword: String?)
    case password(username: String, encPassword: String)
    case integration(clientId: String, encSecret: String)

    private enum CodingKeys: String, CodingKey {
        case type, username, encRefreshToken, encPassword, clientId, encSecret
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "admin":
            self = .admin(
                username: try c.decode(String.self, forKey: .username),
                encRefreshToken: try c.decode(String.self, forKey: .encRefreshToken),
                encPassword: try c.decodeIfPresent(String.self, forKey: .encPassword)
            )
        case "password":
            self = .password(
                username: try c.decode(String.self, forKey: .username),
                encPassword: try c.decode(String.self, forKey: .encPassword)
            )
        case "integration":
            self = .integration(
                clientId: try c.decode(String.self, forKey: .clientId),
                encSecret: try c.decode(String.self, forKey: .encSecret)
            )
        default:
            throw DecodingError.dataCorruptedError(
                forKey: .type, in: c, debugDescription: "Unknown ShopAuth type"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .admin(username, encRefreshToken, encPassword):
            try c.encode("admin", forKey: .type)
            try c.encode(username, forKey: .username)
            try c.encode(encRefreshToken, forKey: .encRefreshToken)
            try c.encodeIfPresent(encPassword, forKey: .encPassword)
        case let .password(username, encPassword):
            try c.encode("password", forKey: .type)
            try c.encode(username, forKey: .username)
            try c.encode(encPassword, forKey: .encPassword)
        case let .integration(clientId, encSecret):
            try c.encode("integration", forKey: .type)
            try c.encode(clientId, forKey: .clientId)
            try c.encode(encSecret, forKey: .encSecret)
        }
    }
}

// MARK: - Connected shop

/// Per-shop toggles for which product fields are visible/editable in the product detail + edit
/// sheets (mirrors the Android `ProductFieldConfig`).
nonisolated struct ProductFieldConfig: Codable, Equatable, Sendable {
    var showEan = true
    var editEan = true
    var showManufacturerNumber = true
    var editManufacturerNumber = true
    var showPrice = true
    var editPrice = true
    var showDescription = true
    var showManufacturer = true
    var showCategories = true
    var showSalesChannels = true
}

nonisolated struct ConnectedShop: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    /// normalized, no trailing slash
    var baseUrl: String
    var auth: ShopAuth?
    var tintIndex: Int
    var currency: String
    var dailyTarget: Double?
    /// legacy demo-mode flag; demo shops are purged at load
    var demo: Bool
    /// null = instance system language
    var languageId: String?
    /// e.g. de-DE; drives number formatting
    var localeCode: String?
    var lowStockThreshold: Int
    /// entity → read access, from the wizard ACL probes (re-probed on sign-in-again);
    /// empty = never probed (legacy shops) and treated as all-granted
    var scopes: [String: Bool]
    /// per-shop product field visibility/editability
    var productFields: ProductFieldConfig

    init(
        id: String,
        name: String,
        baseUrl: String,
        auth: ShopAuth? = nil,
        tintIndex: Int = 0,
        currency: String = "EUR",
        dailyTarget: Double? = nil,
        demo: Bool = false,
        languageId: String? = nil,
        localeCode: String? = nil,
        lowStockThreshold: Int = 5,
        scopes: [String: Bool] = [:],
        productFields: ProductFieldConfig = ProductFieldConfig()
    ) {
        self.id = id
        self.name = name
        self.baseUrl = baseUrl
        self.auth = auth
        self.tintIndex = tintIndex
        self.currency = currency
        self.dailyTarget = dailyTarget
        self.demo = demo
        self.languageId = languageId
        self.localeCode = localeCode
        self.lowStockThreshold = lowStockThreshold
        self.scopes = scopes
        self.productFields = productFields
    }

    var tint: ShopTint { TintPalette[((tintIndex % TintPalette.count) + TintPalette.count) % TintPalette.count] }

    nonisolated func canRead(_ entity: String) -> Bool { scopes[entity] ?? true }

    // Additive-decode safety: tolerate older/newer files missing fields (mirrors
    // kotlinx `ignoreUnknownKeys` + defaults).
    enum CodingKeys: String, CodingKey {
        case id, name, baseUrl, auth, tintIndex, currency, dailyTarget, demo
        case languageId, localeCode, lowStockThreshold, scopes, productFields
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        baseUrl = try c.decode(String.self, forKey: .baseUrl)
        auth = try c.decodeIfPresent(ShopAuth.self, forKey: .auth)
        tintIndex = try c.decodeIfPresent(Int.self, forKey: .tintIndex) ?? 0
        currency = try c.decodeIfPresent(String.self, forKey: .currency) ?? "EUR"
        dailyTarget = try c.decodeIfPresent(Double.self, forKey: .dailyTarget)
        demo = try c.decodeIfPresent(Bool.self, forKey: .demo) ?? false
        languageId = try c.decodeIfPresent(String.self, forKey: .languageId)
        localeCode = try c.decodeIfPresent(String.self, forKey: .localeCode)
        lowStockThreshold = try c.decodeIfPresent(Int.self, forKey: .lowStockThreshold) ?? 5
        scopes = try c.decodeIfPresent([String: Bool].self, forKey: .scopes) ?? [:]
        productFields = try c.decodeIfPresent(ProductFieldConfig.self, forKey: .productFields) ?? ProductFieldConfig()
    }
}

// MARK: - Snapshot value types

nonisolated struct RecentOrder: Codable, Equatable, Identifiable, Sendable {
    var id: String
    var orderNumber: String
    var customer: String
    var state: String
    var stateTechnical: String
    /// in the order's currency
    var amount: Double
    /// null = assume the shop default (legacy snapshots)
    var currencyIso: String?
    /// 0 = unknown (legacy snapshots); rendered as "just now"
    var placedMs: Int64
    var customerEmail: String?
    var company: String?
    var salesChannel: String?
    var paymentState: String?
    var paymentStateTechnical: String?
    var deliveryState: String?
    var deliveryStateTechnical: String?
    var paymentMethod: String?
    var shippingMethod: String?

    init(
        id: String = "",
        orderNumber: String,
        customer: String,
        state: String,
        stateTechnical: String,
        amount: Double,
        currencyIso: String? = nil,
        placedMs: Int64 = 0
    ) {
        self.id = id
        self.orderNumber = orderNumber
        self.customer = customer
        self.state = state
        self.stateTechnical = stateTechnical
        self.amount = amount
        self.currencyIso = currencyIso
        self.placedMs = placedMs
    }
}

nonisolated struct TopCustomer: Codable, Equatable, Identifiable, Sendable {
    var name: String
    var orderCount: Int
    var totalSpend: Double
    var id: String { name }
}

nonisolated struct ShopPromo: Codable, Equatable, Identifiable, Sendable {
    var name: String
    var detail: String
    var status: PromoStatus
    var window: String
    var redemptions: Int
    var id: String
    var active: Bool
    var useIndividualCodes: Bool

    init(
        name: String,
        detail: String,
        status: PromoStatus,
        window: String,
        redemptions: Int,
        id: String = "",
        active: Bool = false,
        useIndividualCodes: Bool = false
    ) {
        self.name = name
        self.detail = detail
        self.status = status
        self.window = window
        self.redemptions = redemptions
        self.id = id
        self.active = active
        self.useIndividualCodes = useIndividualCodes
    }
}

nonisolated struct TopProduct: Codable, Equatable, Identifiable, Sendable {
    var name: String
    var quantity: Int
    var revenue: Double
    var id: String { name }
}

nonisolated struct LowStockItem: Codable, Equatable, Identifiable, Sendable {
    var name: String
    var stock: Int
    var id: String

    init(name: String, stock: Int, id: String = "") {
        self.name = name
        self.stock = stock
        self.id = id
    }
}

nonisolated struct ShopSnapshot: Codable, Equatable, Sendable {
    var todayRevenue: Double = 0
    var yesterdayRevenue: Double = 0
    var ordersToday: Int = 0
    var openOrders: Int = 0
    var unpaidOrders: Int = 0
    var lowStockCount: Int = 0
    var lowStockItems: [LowStockItem] = []
    var weekRevenue: [Double] = []
    var todayIndex: Int = 6
    var recentOrders: [RecentOrder] = []
    var topCustomers: [TopCustomer] = []
    var promos: [ShopPromo] = []
    var topProducts: [TopProduct] = []
    var pendingReviews: Int = 0
    var shopwareVersion: String?
    var lastSyncEpochMs: Int64 = 0
}

// MARK: - Top-level persisted state

nonisolated struct AppData: Codable, Equatable, Sendable {
    var shops: [ConnectedShop] = []
    /// populated at runtime by the repository from per-shop snapshot files; persisted
    /// only by legacy versions (migrated out of app-data.json at first load)
    var snapshots: [String: ShopSnapshot] = [:]
    var selectedShopId: String?
    var onboardingSeen: Bool = false
    var syncEnabled: Bool = false
    var notifyLowStock: Bool = false
    var notifyUnpaid: Bool = false
    /// Stable per-installation id used as the `ce_fcn` row id for FCM push registration.
    var pushInstallId: String = ""

    enum CodingKeys: String, CodingKey {
        case shops, snapshots, selectedShopId, onboardingSeen, syncEnabled, notifyLowStock, notifyUnpaid, pushInstallId
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        shops = try c.decodeIfPresent([ConnectedShop].self, forKey: .shops) ?? []
        snapshots = try c.decodeIfPresent([String: ShopSnapshot].self, forKey: .snapshots) ?? [:]
        selectedShopId = try c.decodeIfPresent(String.self, forKey: .selectedShopId)
        onboardingSeen = try c.decodeIfPresent(Bool.self, forKey: .onboardingSeen) ?? false
        syncEnabled = try c.decodeIfPresent(Bool.self, forKey: .syncEnabled) ?? false
        notifyLowStock = try c.decodeIfPresent(Bool.self, forKey: .notifyLowStock) ?? false
        notifyUnpaid = try c.decodeIfPresent(Bool.self, forKey: .notifyUnpaid) ?? false
        pushInstallId = try c.decodeIfPresent(String.self, forKey: .pushInstallId) ?? ""
    }
}
