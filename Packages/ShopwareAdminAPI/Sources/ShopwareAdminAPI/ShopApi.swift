import Foundation

/// The per-shop facade: `repository(_:)` plus action services for `/_action`/`/_admin` endpoints.
public final class ShopApi: Sendable {
    private let client: ShopwareClient

    public let stateMachine: StateMachineApi
    public let dashboard: DashboardStatsApi
    public let documents: DocumentApi
    public let promotions: PromotionApi
    public let media: MediaApi
    public let instance: InstanceApi
    public let customers: CustomerApi
    public let customerOrders: CustomerOrderApi
    public let orders: OrderApi

    public init(
        baseURL: String,
        auth: PlainAuth,
        context: ApiContext = ApiContext(),
        transport: HTTPTransport = URLSessionTransport(),
        onRefreshToken: (@Sendable (String) async -> Void)? = nil
    ) {
        let client = ShopwareClient(
            baseURL: baseURL,
            auth: auth,
            context: context,
            transport: transport,
            onRefreshToken: onRefreshToken
        )
        self.client = client
        self.stateMachine = StateMachineApi(client: client)
        self.dashboard = DashboardStatsApi(client: client)
        self.documents = DocumentApi(client: client)
        self.promotions = PromotionApi(client: client)
        self.media = MediaApi(client: client)
        self.instance = InstanceApi(client: client)
        self.customers = CustomerApi(client: client)
        self.customerOrders = CustomerOrderApi(client: client)
        self.orders = OrderApi(client: client)
    }

    /// The latest rotated refresh token — read by the connect wizard after verify.
    public var currentRefreshToken: String? {
        get async { await client.currentRefreshToken }
    }

    public func repository(_ entityName: String) -> EntityRepository {
        EntityRepository(client: client, entityName: entityName)
    }

    public func permissions() async throws -> AdminPermissions {
        try await client.adminPermissions()
    }
}

public struct MediaApi: Sendable {
    let client: ShopwareClient

    private func repository(_ name: String) -> EntityRepository {
        EntityRepository(client: client, entityName: name)
    }

    /// Creates a media entity (optionally inside a folder), uploads the binary, returns the id.
    @discardableResult
    public func uploadImage(
        bytes: Data,
        extension ext: String = "jpg",
        fileName: String? = nil,
        mediaFolderId: String? = nil
    ) async throws -> String {
        try await upload(bytes: bytes, extension: ext, fileName: fileName,
                         mimeType: ext == "png" ? "image/png" : "image/jpeg", mediaFolderId: mediaFolderId)
    }

    /// Uploads the original file, preserving its name, extension and content type.
    @discardableResult
    public func upload(bytes: Data, extension ext: String, fileName: String?, mimeType: String,
                       mediaFolderId: String? = nil) async throws -> String {
        let mediaId = Self.newId()
        var create: [String: JSONValue] = ["id": .string(mediaId)]
        if let mediaFolderId { create["mediaFolderId"] = .string(mediaFolderId) }
        try await repository("media").create(.object(create))

        let name = (fileName ?? "app-\(mediaId)").addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? mediaId
        let fileExtension = ext.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        do {
            try await client.postBytes("/_action/media/\(mediaId)/upload?extension=\(fileExtension)&fileName=\(name)",
                                       bytes: bytes, mimeType: mimeType)
        } catch {
            // Only roll back a confirmed rejection. A lost response may mean the upload succeeded.
            if let apiError = error as? ApiError {
                switch apiError {
                case .validation, .forbidden, .notFound:
                    try? await repository("media").delete(mediaId)
                default: break
                }
            }
            throw error
        }
        return mediaId
    }

    public func rename(_ id: String, fileName: String) async throws {
        try await client.actionPost("/_action/media/\(id)/rename", body: .object(["fileName": .string(fileName)]))
    }

    /// Verified payload (6.7.8): empty configuration object is enough.
    @discardableResult
    public func createFolder(name: String, parentId: String?) async throws -> String {
        let id = Self.newId()
        var payload: [String: JSONValue] = [
            "id": .string(id),
            "name": .string(name),
            "configuration": .object([:]),
        ]
        if let parentId { payload["parentId"] = .string(parentId) }
        try await repository("media-folder").create(.object(payload))
        return id
    }

    /// Uploads the image and attaches it to the product as cover.
    public func uploadProductCover(productId: String, bytes: Data, extension ext: String = "jpg") async throws {
        let mediaId = try await uploadImage(bytes: bytes, extension: ext)
        let productMediaId = Self.newId()
        try await repository("product").patch(productId, .object([
            "coverId": .string(productMediaId),
            "media": .array([.object([
                "id": .string(productMediaId),
                "mediaId": .string(mediaId),
                "position": .int(0),
            ])]),
        ]))
    }

    static func newId() -> String {
        UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    }
}

public struct PromotionApi: Sendable {
    let client: ShopwareClient

    private func repository(_ name: String) -> EntityRepository {
        EntityRepository(client: client, entityName: name)
    }

    public func setActive(promotionId: String, active: Bool) async throws {
        try await repository("promotion").patch(promotionId, .object(["active": .bool(active)]))
    }

    /// Only valid for promotions configured with useIndividualCodes.
    public func addIndividualCodes(promotionId: String, amount: Int) async throws {
        try await client.actionPost("/_action/promotion/codes/add-individual", body: .object([
            "promotionId": .string(promotionId),
            "amount": .int(amount),
        ]))
    }
}

public struct StateMachineApi: Sendable {
    let client: ShopwareClient

    /// entity: order | order_transaction | order_delivery
    public func transitions(entity: String, id: String) async throws -> [StateTransition] {
        let response = try await client.getJSON("/_action/state-machine/\(entity)/\(id)/state")
        guard case let .array(items)? = response["transitions"] else { return [] }
        return items.compactMap { value -> StateTransition? in
            guard case .object = value else { return nil }
            let t = SwEntity(value)
            guard let action = t.string("actionName"), let url = t.string("url") else { return nil }
            let technical = t.string("toStateName") ?? action
            let display = t.string("name") ?? Self.humanize(technical)
            return StateTransition(
                actionName: action,
                toStateName: technical,
                displayName: display,
                url: url.hasPrefix("/api") ? String(url.dropFirst(4)) : url
            )
        }
    }

    private static func humanize(_ technical: String) -> String {
        let spaced = technical.replacingOccurrences(of: "_", with: " ")
        guard let first = spaced.first else { return spaced }
        return first.uppercased() + spaced.dropFirst()
    }

    public func transition(url: String) async throws {
        try await client.actionPost(url)
    }

    /// Entity-specific endpoint carrying confirmation-mail options.
    public func transitionWithOptions(
        entity: String,
        entityId: String,
        actionName: String,
        sendMail: Bool,
        documentIds: [String],
        internalComment: String?
    ) async throws {
        var body: [String: JSONValue] = [
            "sendMail": .bool(sendMail),
            "documentIds": .array(documentIds.map { .string($0) }),
        ]
        if let internalComment, !internalComment.isEmpty {
            body["internalComment"] = .string(internalComment)
        }
        try await client.actionPost("/_action/\(entity)/\(entityId)/state/\(actionName)", body: .object(body))
    }
}

public struct DashboardStatsApi: Sendable {
    let client: ShopwareClient

    /// date ("yyyy-MM-dd") -> (orderCount, revenue); timezone-aware, same source as sw-dashboard.
    public func orderAmount(
        since: String,
        timezone: String,
        paid: Bool
    ) async throws -> [String: (count: Int, revenue: Double)] {
        let tz = timezone.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? timezone
        let result = try await client.getJSON("/_admin/dashboard/order-amount/\(since)?timezone=\(tz)&paid=\(paid)")
        guard case let .array(items)? = result["statistic"] else { return [:] }
        var out: [String: (count: Int, revenue: Double)] = [:]
        for value in items {
            guard case .object = value else { continue }
            let e = SwEntity(value)
            out[e.string("date") ?? ""] = (e.int("count") ?? 0, e.double("amount") ?? 0.0)
        }
        return out
    }
}

public struct InstanceApi: Sendable {
    let client: ShopwareClient

    private func repository(_ name: String) -> EntityRepository {
        EntityRepository(client: client, entityName: name)
    }

    public func version() async throws -> String {
        SwEntity(try await client.getJSON("/_info/version")).string("version") ?? "unknown"
    }

    public func probe(_ entity: String) async -> Bool {
        await swallowing {
            _ = try await repository(entity).search(
                Criteria().setLimit(1).setTotalCountMode(.none)
            )
            return true
        } ?? false
    }

    public func defaultCurrencyIso() async -> String? {
        await swallowing {
            try await repository("currency").search(
                Criteria()
                    .setLimit(1)
                    .addFilter(Criteria.equals("factor", .number(1.0)))
                    .addIncludes("currency", ["isoCode"])
            ).data.first?.string("isoCode")
        }
    }

    public func defaultSalesChannelName() async -> String? {
        await swallowing {
            try await repository("sales-channel").search(
                Criteria()
                    .setLimit(1)
                    .addIncludes("sales_channel", ["name", "translated"])
            ).data.first?.translated("name")
        }
    }

    /// Best-effort probes: failures become nil, but cancellation must propagate.
    private func swallowing<T>(_ block: () async throws -> T?) async -> T? {
        do {
            return try await block()
        } catch is CancellationError {
            return nil
        } catch {
            return nil
        }
    }

    public func languages() async throws -> [LanguageOption] {
        try await repository("language").search(
            Criteria()
                .setLimit(25)
                .addAssociation("locale")
                .addIncludes("language", ["id", "name", "locale", "translated"])
                .addIncludes("locale", ["code"])
        ).data.compactMap { language in
            guard let id = language.id else { return nil }
            return LanguageOption(
                id: id,
                name: language.translated("name") ?? "—",
                localeCode: language.entity("locale")?.string("code")
            )
        }
    }
}
