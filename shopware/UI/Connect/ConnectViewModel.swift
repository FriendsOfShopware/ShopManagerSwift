import Foundation
import Observation
import ShopwareAdminAPI

let systemLanguageId = "2fbb5fe2e29a4d70aa5854ce7ce3e20b"

struct ScopeProbe: Identifiable, Equatable {
    let entity: String
    let label: String
    let ok: Bool
    var id: String { entity }
}

struct VerifyState: Equatable {
    var running = false
    var connected = false
    var version: String?
    var scopes: [ScopeProbe] = []
    var error: String?
}

/// Drives the 4-step connect wizard: URL probe → admin login → ACL verify → personalize.
/// The verify `ShopApi`'s client holds the rotating refresh token that `finish` persists — the
/// password itself is never stored.
@MainActor
@Observable
final class ConnectViewModel {
    private let repo: AppRepository

    /// 0 url · 1 credentials · 2 verify · 3 personalize
    private(set) var step = 0
    private(set) var busy = false

    var url = ""
    var urlError: String?

    var username = ""
    var password = ""

    private var verifyApi: ShopApi?
    private(set) var verify = VerifyState()

    var shopName = ""
    var tintIndex = 0
    var currency = "EUR"
    var dailyTarget = ""
    private(set) var languages: [LanguageOption] = []
    var selectedLanguage: LanguageOption?

    private(set) var normalizedUrl = ""

    init(repo: AppRepository) {
        self.repo = repo
    }

    func submitUrl() {
        if busy { return }
        busy = true
        urlError = nil
        Task {
            let norm = ShopwareHttp.normalizeBaseUrl(url)
            let result = await ShopwareHttp.probeShopware(norm)
            switch result {
            case .success:
                normalizedUrl = norm
                step = 1
            case let .failure(error):
                urlError = (error as? ApiError)?.message
                    ?? "Couldn't reach a Shopware shop at \(norm)"
            }
            busy = false
        }
    }

    var credsValid: Bool {
        !username.trimmingCharacters(in: .whitespaces).isEmpty && !password.isEmpty
    }

    func startVerify() {
        step = 2
        verify = VerifyState(running: true)
        Task {
            let api = ShopApi(
                baseURL: normalizedUrl,
                auth: .password(username: username.trimmingCharacters(in: .whitespaces), password: password, refreshToken: nil)
            )
            verifyApi = api
            do {
                let version = try await api.instance.version()
                let labels: [String: String] = [
                    "order": "Orders",
                    "product": "Products",
                    "customer": "Customers",
                    "promotion": "Promotions",
                    "product_review": "Reviews",
                    "media": "Media",
                ]
                var scopes: [ScopeProbe] = []
                for entity in AppRepository.probeEntities {
                    let ok = await api.instance.probe(entity)
                    scopes.append(ScopeProbe(entity: entity, label: labels[entity] ?? entity, ok: ok))
                }
                if let iso = await api.instance.defaultCurrencyIso() { currency = iso }
                shopName = await api.instance.defaultSalesChannelName()
                    ?? URL(string: normalizedUrl)?.host() ?? ""
                languages = (try? await api.instance.languages()) ?? []
                selectedLanguage = languages.first { $0.id == systemLanguageId } ?? languages.first
                verify = VerifyState(connected: true, version: version, scopes: scopes)
            } catch let ApiError.forbidden(message, missingPrivileges) {
                let missing = missingPrivileges.isEmpty ? "" : " Missing: \(missingPrivileges.joined(separator: ", "))"
                verify = VerifyState(error: message + missing)
            } catch {
                verify = VerifyState(error: (error as? ApiError)?.message ?? "Could not connect")
            }
        }
    }

    var canLeaveVerify: Bool {
        verify.connected && verify.scopes.contains { $0.ok }
    }

    func toPersonalize() { step = 3 }

    func retryFromCredentials() {
        verify = VerifyState()
        step = 1
    }

    /// Returns false when there is nowhere left to go back to (wizard should close).
    @discardableResult
    func goBack() -> Bool {
        if busy || verify.running { return true }
        switch step {
        case 0: return false
        case 2: verify = VerifyState(); step = 1; return true
        default: step -= 1; return true
        }
    }

    func finish(onDone: @escaping (String) -> Void) {
        if busy { return }
        Task {
            guard let refreshToken = await verifyApi?.currentRefreshToken else {
                retryFromCredentials()
                return
            }
            busy = true
            let trimmedName = shopName.trimmingCharacters(in: .whitespaces)
            guard let enc = try? Crypto.encrypt(refreshToken) else {
                busy = false
                retryFromCredentials()
                return
            }
            // Persist the password (encrypted) so a revoked refresh token can be recovered silently.
            let encPassword = try? Crypto.encrypt(password)
            let shop = ConnectedShop(
                id: UUID().uuidString,
                name: trimmedName.isEmpty ? "My Shop" : trimmedName,
                baseUrl: normalizedUrl,
                auth: .admin(username: username.trimmingCharacters(in: .whitespaces), encRefreshToken: enc, encPassword: encPassword),
                tintIndex: tintIndex,
                currency: currency,
                dailyTarget: Double(dailyTarget.trimmingCharacters(in: .whitespaces)),
                languageId: selectedLanguage?.id,
                localeCode: selectedLanguage?.localeCode,
                scopes: Dictionary(uniqueKeysWithValues: verify.scopes.map { ($0.entity, $0.ok) })
            )
            await repo.addShop(shop)
            busy = false
            onDone(shop.id)
        }
    }
}
