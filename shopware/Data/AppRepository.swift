import Foundation
import Observation
import ShopwareAdminAPI
#if canImport(WidgetKit)
import WidgetKit
#endif

/// Per-shop state holder and screen-level data facade (the Apple analogue of the Android
/// `AppRepository`). Owns the persisted `AppData`, caches one `ShopApi` per shop, recombines the
/// settings store with per-shop snapshot files, and exposes suspend-style async functions for
/// every screen. `@Observable` + `@MainActor` so SwiftUI views observe `data` directly.
@MainActor
@Observable
final class AppRepository {
    /// Entities whose read access is probed at connect and on sign-in-again; when adding a feature
    /// that needs a new privilege, extend this list.
    static let probeEntities = ["order", "product", "customer", "promotion", "product_review", "media"]

    /// The combined app state (settings/auth from `AppStore` + snapshots from `SnapshotStore`).
    /// Views read this; mutations flow through the methods below.
    private(set) var data = AppData()

    @ObservationIgnored private let appStore: AppStore
    @ObservationIgnored private let snapshotStore: SnapshotStore
    @ObservationIgnored private let supportDir: URL
    @ObservationIgnored private var apis: [String: ShopApi] = [:]
    @ObservationIgnored private let apiFactory: ((ConnectedShop) -> ShopApi)?

    init(directory: URL? = nil, apiFactory: ((ConnectedShop) -> ShopApi)? = nil) {
        self.apiFactory = apiFactory
        let dir = directory ?? SharedStorage.containerURL
        self.supportDir = dir
        self.appStore = AppStore(directory: dir)
        self.snapshotStore = SnapshotStore(dir: dir.appendingPathComponent("snapshots"))
    }

    /// Loads persisted state and migrates legacy in-file snapshots out to per-shop cache files.
    func bootstrap() async {
        var loaded = snapshotStore.loadAll()
        var stored = await appStore.load()

        // one-time migration: older versions persisted snapshots inside app-data.json
        if !stored.snapshots.isEmpty {
            for (id, snap) in stored.snapshots { snapshotStore.write(id, snap) }
            loaded.merge(stored.snapshots) { _, new in new }
            stored.snapshots = [:]
            await appStore.save(stored)
        }
        stored.snapshots = loaded
        data = stored
    }

    // MARK: - Per-shop API cache

    func apiFor(_ shop: ConnectedShop) -> ShopApi {
        if let existing = apis[shop.id] { return existing }
        let api = apiFactory?(shop) ?? ShopApi(
            baseURL: shop.baseUrl,
            auth: shop.plainAuth(),
            context: ApiContext(languageId: shop.languageId),
            onRefreshToken: { [weak self] rotated in
                await self?.persistRefreshToken(shopId: shop.id, refreshToken: rotated)
            }
        )
        apis[shop.id] = api
        return api
    }

    // MARK: - Persistence plumbing

    /// Applies a mutation to the in-memory state and persists it. Snapshots are runtime-only
    /// (per-shop cache files), so they're stripped before saving and restored after.
    private func mutate(_ transform: (inout AppData) -> Void) async {
        let snapshots = data.snapshots
        var copy = data
        transform(&copy)
        let toPersist = { var p = copy; p.snapshots = [:]; return p }()
        await appStore.save(toPersist)
        copy.snapshots = snapshots
        data = copy
    }

    /// Called by the API client on every refresh-token rotation; also migrates legacy password-auth
    /// shops to Admin auth on their first successful grant.
    private func persistRefreshToken(
        shopId: String, refreshToken: String, username: String? = nil, encPassword: String? = nil
    ) async {
        guard let enc = try? Crypto.encrypt(refreshToken) else { return }
        await mutate { d in
            d.shops = d.shops.map { shop in
                guard shop.id == shopId else { return shop }
                var updated = shop
                let resolvedUser: String
                var existingPassword: String?
                switch shop.auth {
                case let .admin(u, _, pw): resolvedUser = u; existingPassword = pw
                case let .password(u, pw): resolvedUser = u; existingPassword = pw
                default: resolvedUser = ""
                }
                // Preserve the stored password across rotations (or adopt a freshly-supplied one).
                updated.auth = .admin(
                    username: username ?? resolvedUser,
                    encRefreshToken: enc,
                    encPassword: encPassword ?? existingPassword
                )
                return updated
            }
        }
    }

    // MARK: - Auth

    /// Validates the credentials, stores the new session and refreshes the snapshot.
    func reauthenticate(shop: ConnectedShop, username: String, password: String) async throws {
        apis.removeValue(forKey: shop.id)
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        // Persist the password (encrypted) so future token revocations recover silently.
        let encPassword = try? Crypto.encrypt(password)
        let api = ShopApi(
            baseURL: shop.baseUrl,
            auth: .password(username: user, password: password, refreshToken: nil),
            context: ApiContext(languageId: shop.languageId),
            onRefreshToken: { [weak self] rotated in
                await self?.persistRefreshToken(
                    shopId: shop.id, refreshToken: rotated, username: user, encPassword: encPassword
                )
            }
        )
        _ = try await api.instance.version() // forces the grant; throws ApiError on bad credentials
        // privileges may differ for the new login — re-probe and persist
        var scopes: [String: Bool] = [:]
        for entity in Self.probeEntities {
            scopes[entity] = await api.instance.probe(entity)
        }
        await mutate { d in
            d.shops = d.shops.map { $0.id == shop.id ? { var s = $0; s.scopes = scopes; return s }($0) : $0 }
        }
        apis[shop.id] = api
        _ = await refresh(shopId: shop.id)
    }

    // MARK: - Snapshot refresh

    @discardableResult
    func refresh(shopId: String) async -> Result<Void, Error> {
        guard let shop = data.shops.first(where: { $0.id == shopId }) else {
            return .failure(ApiError.notFound(message: "Shop not found"))
        }
        // Resolve the shop's ShopApi up front (on the main actor) and hand the data source a
        // closure that just returns it — the api cache itself is only mutated here.
        let api = apiFor(shop)
        let source = ShopwareDataSource(apiFor: { _ in api })
        do {
            let snapshot = try await source.fetchSnapshot(shop: shop, lowStockThreshold: shop.lowStockThreshold)
            snapshotStore.write(shopId, snapshot)
            data.snapshots[shopId] = snapshot
            reloadWidgets()
            return .success(())
        } catch {
            return .failure(error)
        }
    }

    // MARK: - Shop management

    func addShop(_ shop: ConnectedShop) async {
        await mutate { d in
            d.shops.append(shop)
            d.selectedShopId = shop.id
            d.onboardingSeen = true
        }
    }

    func removeShop(id: String) async {
        apis.removeValue(forKey: id)
        snapshotStore.delete(id)
        data.snapshots.removeValue(forKey: id)
        await mutate { d in
            d.shops.removeAll { $0.id == id }
            if d.selectedShopId == id { d.selectedShopId = d.shops.first?.id }
        }
    }

    func selectShop(id: String) async {
        await mutate { $0.selectedShopId = id }
        reloadWidgets() // the widget follows the selected shop
    }

    private func reloadWidgets() {
        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadAllTimelines()
        #endif
    }

    func markOnboardingSeen() async {
        await mutate { $0.onboardingSeen = true }
    }

    func setSyncEnabled(_ enabled: Bool) async { await mutate { $0.syncEnabled = enabled } }
    func setNotifyLowStock(_ enabled: Bool) async { await mutate { $0.notifyLowStock = enabled } }
    func setNotifyUnpaid(_ enabled: Bool) async { await mutate { $0.notifyUnpaid = enabled } }

    func updateShopSettings(
        shopId: String,
        name: String,
        tintIndex: Int,
        dailyTarget: Double?,
        lowStockThreshold: Int
    ) async {
        guard let old = data.shops.first(where: { $0.id == shopId }) else { return }
        await mutate { d in
            d.shops = d.shops.map {
                guard $0.id == shopId else { return $0 }
                var s = $0
                s.name = name
                s.tintIndex = tintIndex
                s.dailyTarget = dailyTarget
                s.lowStockThreshold = lowStockThreshold
                return s
            }
        }
        // The snapshot's low-stock count/items were computed with the old threshold.
        if old.lowStockThreshold != lowStockThreshold { _ = await refresh(shopId: shopId) }
    }

    func setProductFields(shopId: String, _ config: ProductFieldConfig) async {
        await mutate { d in
            d.shops = d.shops.map {
                guard $0.id == shopId else { return $0 }
                var s = $0
                s.productFields = config
                return s
            }
        }
    }

    func languagesFor(_ shop: ConnectedShop) async throws -> [LanguageOption] {
        try await apiFor(shop).instance.languages()
    }

    func setShopLanguage(shopId: String, language: LanguageOption?) async {
        apis.removeValue(forKey: shopId)
        await mutate { d in
            d.shops = d.shops.map {
                guard $0.id == shopId else { return $0 }
                var s = $0
                s.languageId = language?.id
                s.localeCode = language?.localeCode
                return s
            }
        }
        _ = await refresh(shopId: shopId)
    }

    // MARK: - Screen-level data facades

    func orderDetail(_ shop: ConnectedShop, orderId: String) async throws -> OrderDetail {
        try await apiFor(shop).fetchOrderDetail(orderId)
    }

    func orderTimeline(_ shop: ConnectedShop, referencedIds: [String]) async throws -> [OrderTimelineEntry] {
        try await apiFor(shop).fetchOrderTimeline(referencedIds: referencedIds)
    }

    func customerDetail(_ shop: ConnectedShop, customerId: String) async throws -> CustomerDetail? {
        try await apiFor(shop).fetchCustomerDetail(customerId)
    }

    func saveCustomerContact(
        _ shop: ConnectedShop, customerId: String, firstName: String, lastName: String,
        email: String, salutationId: String?, title: String?, company: String?
    ) async throws {
        try await apiFor(shop).saveCustomerContact(
            customerId: customerId, firstName: firstName, lastName: lastName, email: email,
            salutationId: salutationId, title: title, company: company
        )
    }

    func saveCustomerAddress(_ shop: ConnectedShop, address: EditableAddress) async throws {
        try await apiFor(shop).saveCustomerAddress(address)
    }

    func salutations(_ shop: ConnectedShop) async throws -> [SalutationOption] {
        try await apiFor(shop).fetchSalutations()
    }

    func countries(_ shop: ConnectedShop) async throws -> [CountryOption] {
        try await apiFor(shop).fetchCountries()
    }

    func productQuickInfo(_ shop: ConnectedShop, productId: String) async throws -> ProductQuickInfo? {
        try await apiFor(shop).fetchProductQuickInfo(productId)
    }

    func saveProductQuickEdit(
        _ shop: ConnectedShop, info: ProductQuickInfo, stock: Int, active: Bool, price: PriceEdit?
    ) async throws {
        try await apiFor(shop).saveProductQuickEdit(info, stock: stock, active: active, price: price)
    }

    func productDetail(_ shop: ConnectedShop, productId: String) async throws -> ProductDetail? {
        try await apiFor(shop).fetchProductDetail(productId, shop.baseUrl)
    }

    func productVariants(_ shop: ConnectedShop, parentId: String, parentTaxRate: Double?) async throws -> [ProductVariant] {
        try await apiFor(shop).fetchProductVariants(parentId, parentTaxRate: parentTaxRate)
    }

    func saveProductDetail(
        _ shop: ConnectedShop, detail: ProductDetail, name: String,
        active: Bool, stock: Int, ean: String?, manufacturerNumber: String?, price: PriceEdit?
    ) async throws {
        try await apiFor(shop).saveProductDetail(
            detail, name: name, active: active, stock: stock,
            ean: ean, manufacturerNumber: manufacturerNumber, price: price
        )
    }

    func saveVariantEdit(_ shop: ConnectedShop, variant: ProductVariant, stock: Int, price: PriceEdit?) async throws {
        try await apiFor(shop).saveVariantEdit(variant, stock: stock, price: price)
    }

    func uploadProductPhoto(_ shop: ConnectedShop, productId: String, bytes: Data) async throws {
        try await apiFor(shop).media.uploadProductCover(productId: productId, bytes: bytes)
    }

    // MARK: - Analytics (Reports)

    func loadKpi(_ shop: ConnectedShop, type: KpiType, filters: AnalyticsFilters) async throws -> KpiState {
        let api = apiFor(shop)
        switch type {
        case .totalSales: return .timeSeries(try await api.analyticsTotalSales(filters))
        case .orderCount: return .timeSeries(try await api.analyticsOrderCount(filters))
        case .avgOrderValue: return .timeSeries(try await api.analyticsAvgOrderValue(filters))
        case .newCustomers: return .timeSeries(try await api.analyticsNewCustomers(filters))
        case .salesChannel: return .breakdown(try await api.analyticsSalesChannel(filters))
        case .paymentMethod: return .breakdown(try await api.analyticsPaymentMethod(filters))
        case .shippingMethod: return .breakdown(try await api.analyticsShippingMethod(filters))
        case .country: return .breakdown(try await api.analyticsCountry(filters))
        case .bestSellingProduct: return .breakdown(try await api.analyticsBestSelling(filters))
        case .manufacturer: return .breakdown(try await api.analyticsManufacturer(filters))
        case .promotionCode: return .breakdown(try await api.analyticsPromotionCode(filters))
        case .customerCount: return .single(try await api.analyticsCustomerCount(filters))
        }
    }

    func loadShopRevenue(_ shop: ConnectedShop, filters: AnalyticsFilters) async throws -> Double {
        try await apiFor(shop).analyticsRevenueTotal(filters)
    }

    func analyticsFilterOptions(_ shop: ConnectedShop) async -> AnalyticsFilterOptions {
        await apiFor(shop).fetchAnalyticsFilterOptions()
    }

    func mediaFolders(_ shop: ConnectedShop, parentId: String?) async throws -> [MediaFolderItem] {
        try await apiFor(shop).repository("media-folder").search(mediaFolderCriteria(parentId))
            .data.map(parseMediaFolder)
    }

    func createMediaFolder(_ shop: ConnectedShop, parentId: String?, name: String) async throws -> String {
        try await apiFor(shop).media.createFolder(name: name, parentId: parentId)
    }

    @discardableResult
    func uploadMedia(_ shop: ConnectedShop, folderId: String?, bytes: Data, extension ext: String) async throws -> String {
        try await apiFor(shop).media.uploadImage(bytes: bytes, extension: ext, mediaFolderId: folderId)
    }

    func deleteMedia(_ shop: ConnectedShop, mediaId: String) async throws {
        try await apiFor(shop).repository("media").delete(mediaId)
    }

    func setPromotionActive(_ shop: ConnectedShop, promotionId: String, active: Bool) async throws {
        try await apiFor(shop).promotions.setActive(promotionId: promotionId, active: active)
    }

    func addPromotionCodes(_ shop: ConnectedShop, promotionId: String, amount: Int) async throws {
        try await apiFor(shop).promotions.addIndividualCodes(promotionId: promotionId, amount: amount)
    }

    func setTrackingCodes(_ shop: ConnectedShop, deliveryId: String, codes: [String]) async throws {
        try await apiFor(shop).setTrackingCodes(deliveryId: deliveryId, codes: codes)
    }

    func setInternalComment(_ shop: ConnectedShop, orderId: String, comment: String?) async throws {
        try await apiFor(shop).setInternalComment(orderId: orderId, comment: comment)
    }

    func generateDocument(_ shop: ConnectedShop, orderId: String, type: String) async throws {
        try await apiFor(shop).documents.create(orderId: orderId, type: type)
    }

    func downloadDocument(_ shop: ConnectedShop, documentId: String, deepLinkCode: String) async throws -> Data {
        try await apiFor(shop).documents.download(documentId: documentId, deepLinkCode: deepLinkCode)
    }

    func setReviewStatus(_ shop: ConnectedShop, reviewId: String, approved: Bool) async throws {
        try await apiFor(shop).setReviewStatus(reviewId: reviewId, approved: approved)
    }

    func transition(_ shop: ConnectedShop, transitionUrl: String) async throws {
        try await apiFor(shop).stateMachine.transition(url: transitionUrl)
    }

    func transitionOrderState(
        _ shop: ConnectedShop, entity: String, entityId: String, actionName: String,
        sendMail: Bool, documentIds: [String], internalComment: String?
    ) async throws {
        try await apiFor(shop).stateMachine.transitionWithOptions(
            entity: entity, entityId: entityId, actionName: actionName,
            sendMail: sendMail, documentIds: documentIds, internalComment: internalComment
        )
    }

    // MARK: - Push (FCM token registration into each shop's ce_fcn entity)

    /// Stable per-installation id (the ce_fcn row id); generated once and persisted.
    func ensurePushInstallId() async -> String {
        if !data.pushInstallId.isEmpty { return data.pushInstallId }
        let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        await mutate { if $0.pushInstallId.isEmpty { $0.pushInstallId = id } }
        return data.pushInstallId
    }

    /// Upsert the device's push token into every connected shop that can read ce_fcn. Best-effort per
    /// shop: a shop without the push app (or without write access) is skipped, not fatal. `platform`
    /// (`apns` on Apple) tells the gateway how to deliver.
    func registerPushToken(_ token: String, platform: String, deviceName: String) async {
        guard !token.isEmpty else { return }
        let installId = await ensurePushInstallId()
        for shop in data.shops {
            try? await apiFor(shop).registerPushToken(
                installId: installId, token: token, platform: platform, deviceName: deviceName
            )
        }
    }

    /// Register against a single shop and report whether the push app is present. A 404 on
    /// /api/ce-fcn means the FroshMobilePush app isn't installed. Other failures are treated as Ok
    /// so we don't nag the user about transient issues.
    func registerPushForShop(_ shop: ConnectedShop, token: String, platform: String, deviceName: String) async -> PushRegisterResult {
        guard !token.isEmpty else { return .ok }
        let installId = await ensurePushInstallId()
        do {
            try await apiFor(shop).registerPushToken(
                installId: installId, token: token, platform: platform, deviceName: deviceName
            )
            return .ok
        } catch ApiError.notFound {
            return .appNotInstalled
        } catch {
            return .ok
        }
    }

    /// Live per-shop push registration status, queried from the shop's ce_fcn.
    func pushStatusForShop(_ shop: ConnectedShop) async -> PushStatus {
        let installId = await ensurePushInstallId()
        do {
            switch try await apiFor(shop).fetchPushRegistration(installId: installId) {
            case let .present(deviceName): return .registered(deviceName: deviceName)
            case .absent: return .notRegistered
            }
        } catch ApiError.notFound {
            return .appNotInstalled
        } catch {
            return .unavailable
        }
    }

    /// Remove this device's ce_fcn row from one shop (the user opting out per-shop).
    func unregisterPushForShop(_ shop: ConnectedShop) async {
        let installId = await ensurePushInstallId()
        await apiFor(shop).unregisterPushToken(installId: installId)
    }
}

/// Result of registering push against a single shop during the connect flow.
enum PushRegisterResult: Equatable, Sendable {
    case ok
    /// The FroshMobilePush app (ce_fcn entity) isn't installed on the shop.
    case appNotInstalled
}

/// Live per-shop push registration state, shown in shop settings.
enum PushStatus: Equatable, Sendable {
    /// This device's row exists; deviceName is what the shop has stored (may be blank/old).
    case registered(deviceName: String?)
    case notRegistered
    /// FroshMobilePush app not installed (ce_fcn entity missing).
    case appNotInstalled
    /// Network/permission failure — don't show a misleading "not registered".
    case unavailable
}

extension ConnectedShop {
    /// Resolves the persisted auth into a usable `PlainAuth`. A failed decrypt (e.g. data restored
    /// to a device without the Keychain key) degrades to a blank token → AuthExpired → sign-in-again,
    /// never a crash. `apiFor` must not throw — it is called synchronously from view-model init.
    func plainAuth() -> PlainAuth {
        switch auth {
        case let .admin(username, encRefreshToken, encPassword):
            // Prefer password auth when we have it: the client uses the refresh token as the fast
            // path but can silently re-grant with the password if that token is revoked. Seed the
            // client's refresh token so the first request still uses it (no needless re-login).
            let token = (try? Crypto.decrypt(encRefreshToken)) ?? ""
            if let encPassword, let password = try? Crypto.decrypt(encPassword) {
                return .password(username: username, password: password, refreshToken: token)
            }
            return .refreshToken(token: token)
        case let .password(username, encPassword):
            if let password = try? Crypto.decrypt(encPassword) {
                return .password(username: username, password: password, refreshToken: nil)
            }
            return .refreshToken(token: "")
        case .integration, .none:
            return .refreshToken(token: "")
        }
    }
}
