import Foundation
import Observation
import ShopwareAdminAPI

let systemLanguageId = "2fbb5fe2e29a4d70aa5854ce7ce3e20b"

enum ConnectStep: Int, CaseIterable, Identifiable {
    case shop, signIn, personalize
    var id: Self { self }
    var title: LocalizedStringResource {
        switch self {
        case .shop: "Your shop"
        case .signIn: "Sign in"
        case .personalize: "Make it yours"
        }
    }
}

struct ScopeProbe: Identifiable, Equatable {
    let entity: String
    let ok: Bool
    var id: String { entity }
    var label: LocalizedStringResource {
        switch entity {
        case "order": "Orders"
        case "product": "Products"
        case "customer": "Customers"
        case "promotion": "Promotions"
        case "product_review": "Reviews"
        default: "Media"
        }
    }
}

struct VerifyState {
    var connected = false
    var version: String?
    var scopes: [ScopeProbe] = []
}

/// Shared setup state. Credentials are encrypted with a device Keychain-backed key on save.
@MainActor
@Observable
final class ConnectViewModel {
    private let repo: AppRepository
    private let transport: any HTTPTransport
    private let encrypt: @MainActor (String) throws -> String
    @ObservationIgnored private(set) var task: Task<Void, Never>?
    @ObservationIgnored private var operation = UUID()
    private var verifyApi: ShopApi?

    private(set) var step: ConnectStep = .shop
    private(set) var busy = false
    private(set) var saving = false
    private(set) var completed = false
    private(set) var status: LocalizedStringResource = "Checking your shop…"
    private(set) var issue: LocalizedStringResource?
    private(set) var verify = VerifyState()
    private(set) var normalizedUrl = ""
    private(set) var languages: [LanguageOption] = []
    private(set) var currency = "EUR"
    var url = ""
    var username = ""
    var password = ""
    var shopName = ""
    var tintIndex = 0
    var selectedLanguage: LanguageOption?

    init(repo: AppRepository, transport: any HTTPTransport = URLSessionTransport(),
         encrypt: @escaping @MainActor (String) throws -> String = Crypto.encrypt) {
        self.repo = repo
        self.transport = transport
        self.encrypt = encrypt
    }

    var canContinue: Bool {
        guard !busy && !completed else { return false }
        switch step {
        case .shop: return !url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .signIn: return !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !password.isEmpty
        case .personalize: return verify.connected && verify.scopes.contains { $0.ok }
        }
    }

    static func normalizedAddress(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: \.isWhitespace) else { return nil }
        let candidate = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard var parts = URLComponents(string: candidate),
              let scheme = parts.scheme?.lowercased(), ["https", "http"].contains(scheme),
              let host = parts.host, !host.isEmpty, parts.user == nil, parts.password == nil else { return nil }
        parts.scheme = scheme
        parts.query = nil
        parts.fragment = nil
        guard let address = parts.url?.absoluteString else { return nil }
        return ShopwareHttp.normalizeBaseUrl(address)
    }

    func submitUrl() {
        guard step == .shop, canContinue else { return }
        guard let address = Self.normalizedAddress(url) else {
            issue = "Enter a valid shop address, such as https://your-shop.com."
            return
        }
        let token = begin("Checking your shop…")
        task = Task {
            let result = await ShopwareHttp.probeShopware(address, transport: transport)
            guard isCurrent(token) else { return }
            busy = false
            switch result {
            case .success:
                normalizedUrl = address
                step = .signIn
            case .failure(let error):
                if case ApiError.unexpected = error {
                    issue = "This address doesn't appear to be a Shopware shop. Check the address and try again."
                } else {
                    issue = "We couldn't reach your shop. Check the address and your internet connection, then try again."
                }
            }
        }
    }

    func signIn() {
        guard step == .signIn, canContinue else { return }
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = password
        let token = begin("Signing in…")
        verify = VerifyState()
        let api = ShopApi(baseURL: normalizedUrl,
                          auth: .password(username: user, password: secret, refreshToken: nil), transport: transport)
        task = Task {
            do {
                let version = try await api.instance.version()
                guard isCurrent(token) else { return }
                status = "Checking access…"
                var scopes: [ScopeProbe] = []
                for entity in AppRepository.probeEntities {
                    let ok = await api.instance.probe(entity)
                    guard isCurrent(token) else { return }
                    scopes.append(ScopeProbe(entity: entity, ok: ok))
                }
                guard scopes.contains(where: { $0.ok }) else {
                    verify = VerifyState(connected: true, version: version, scopes: scopes)
                    issue = "This account can't access any supported area. Ask your shop administrator for access, or use another account."
                    busy = false
                    return
                }
                status = "Getting your shop ready…"
                let detectedCurrency = await api.instance.defaultCurrencyIso()
                guard isCurrent(token) else { return }
                let detectedName = await api.instance.defaultSalesChannelName()
                guard isCurrent(token) else { return }
                let detectedLanguages = (try? await api.instance.languages()) ?? []
                guard isCurrent(token) else { return }
                currency = detectedCurrency ?? "EUR"
                if shopName.isEmpty { shopName = detectedName ?? URL(string: normalizedUrl)?.host() ?? "" }
                languages = detectedLanguages
                selectedLanguage = languages.first { $0.id == selectedLanguage?.id }
                    ?? languages.first { $0.id == systemLanguageId } ?? languages.first
                verify = VerifyState(connected: true, version: version, scopes: scopes)
                verifyApi = api
                step = .personalize
                busy = false
            } catch {
                guard isCurrent(token) else { return }
                busy = false
                switch error {
                case ApiError.auth, ApiError.authExpired, ApiError.validation, ApiError.unexpected(status: 400, message: _):
                    issue = "We couldn't sign you in. Check your admin username and password, then try again."
                case ApiError.forbidden:
                    issue = "This account doesn't have access to the administration. Ask your shop administrator for help."
                default:
                    issue = "The connection was interrupted. Your details are still here; try signing in again."
                }
            }
        }
    }

    func goBack() {
        guard !saving, !completed, step != .shop else { return }
        cancel()
        verifyApi = nil
        verify = VerifyState()
        step = step == .personalize ? .signIn : .shop
    }

    /// Cancelling invalidates late responses even if a transport ignores task cancellation.
    func cancel() {
        guard !saving else { return }
        operation = UUID()
        task?.cancel()
        busy = false
        issue = nil
    }

    func finish(onDone: @escaping (String) -> Void) {
        guard step == .personalize, canContinue else { return }
        let token = begin("Opening your shop…")
        saving = true
        // Snapshot the draft before suspension, and acquire the submission lock synchronously.
        let name = shopName.trimmingCharacters(in: .whitespacesAndNewlines)
        let user = username.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = password
        let tint = tintIndex
        let language = selectedLanguage
        task = Task {
            guard let refreshToken = await verifyApi?.currentRefreshToken, isCurrent(token) else {
                saving = false
                busy = false
                issue = "Your sign-in has expired. Go back and sign in again."
                return
            }
            do {
                let encryptedToken = try encrypt(refreshToken)
                let encryptedPassword = try encrypt(secret)
                let shop = ConnectedShop(
                    id: UUID().uuidString, name: name.isEmpty ? String(localized: "My Shop") : name,
                    baseUrl: normalizedUrl,
                    auth: .admin(username: user, encRefreshToken: encryptedToken, encPassword: encryptedPassword),
                    tintIndex: tint, currency: currency, dailyTarget: nil,
                    languageId: language?.id, localeCode: language?.localeCode,
                    scopes: Dictionary(uniqueKeysWithValues: verify.scopes.map { ($0.entity, $0.ok) })
                )
                await repo.addShop(shop)
                completed = true
                password = ""
                busy = false
                saving = false
                onDone(shop.id)
            } catch {
                saving = false
                busy = false
                issue = "We couldn't securely save your sign-in on this device. Your details are still here; try again."
            }
        }
    }

    private func begin(_ message: LocalizedStringResource) -> UUID {
        task?.cancel()
        operation = UUID()
        issue = nil
        busy = true
        status = message
        return operation
    }

    private func isCurrent(_ token: UUID) -> Bool { operation == token && !Task.isCancelled }
}
