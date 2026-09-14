import Foundation
import Testing
import ShopwareAdminAPI
@testable import shopware

@MainActor
struct ConnectViewModelTests {
    @Test(arguments: [
        (" example.com/admin/ ", "https://example.com"),
        ("https://example.com/shop/admin?foo=bar#section", "https://example.com/shop"),
        ("http://localhost:8000/api", "http://localhost:8000"),
        ("https://example.com/", "https://example.com")
    ])
    func normalizesPastedAddresses(input: String, expected: String) {
        #expect(ConnectViewModel.normalizedAddress(input) == expected)
    }

    @Test(arguments: ["", "   ", "not a shop", "ftp://example.com", "https://", "https://user:secret@example.com"])
    func rejectsMalformedAddresses(input: String) {
        #expect(ConnectViewModel.normalizedAddress(input) == nil)
    }

    @Test func failedChecksAndSignInRetainDraftAndRetry() async {
        let transport = SetupUITestTransport(arguments: ["--setup-fail-url-once", "--setup-fail-login-once"])
        let vm = makeModel(transport: transport)
        vm.url = "setup-ui.test/admin"
        vm.submitUrl(); await vm.task?.value
        #expect(vm.step == .shop && vm.issue != nil && vm.canContinue)
        #expect(vm.url == "setup-ui.test/admin")
        vm.submitUrl(); await vm.task?.value
        #expect(vm.step == .signIn && vm.issue == nil)
        vm.username = " admin "; vm.password = "fixture-password"
        vm.signIn(); await vm.task?.value
        #expect(vm.step == .signIn && vm.issue != nil)
        #expect(vm.username == " admin " && vm.password == "fixture-password")
        vm.signIn(); await vm.task?.value
        #expect(vm.step == .personalize && vm.issue == nil)
        #expect(vm.shopName == "Meadow Studio")
        #expect(vm.selectedLanguage?.localeCode == "en-GB")
    }

    @Test func deniedAccessStaysOnSignInAndPartialAccessCanContinue() async {
        let denied = makeModel(transport: SetupUITestTransport(deniedEntities: Set(AppRepository.probeEntities)))
        await authenticate(denied)
        #expect(denied.step == .signIn && denied.issue != nil)
        #expect(denied.verify.scopes.allSatisfy { !$0.ok })
        let partial = makeModel(transport: SetupUITestTransport(deniedEntities: ["media"]))
        await authenticate(partial)
        #expect(partial.step == .personalize && partial.canContinue)
        #expect(partial.verify.scopes.first { $0.entity == "media" }?.ok == false)
    }

    @Test func backKeepsPersonalizationAndRequiresFreshAuthentication() async {
        let vm = makeModel()
        await authenticate(vm)
        vm.shopName = "My studio"; vm.tintIndex = 2; vm.selectedLanguage = vm.languages.last
        vm.goBack()
        #expect(vm.step == .signIn && !vm.verify.connected)
        #expect(vm.password == "fixture-password" && vm.shopName == "My studio")
        vm.signIn(); await vm.task?.value
        #expect(vm.step == .personalize && vm.shopName == "My studio")
        #expect(vm.tintIndex == 2 && vm.selectedLanguage?.localeCode == "de-DE")
    }

    @Test func completionPersistsOnceAndClearsPassword() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("setup-unit-\(UUID())")
        let repo = AppRepository(directory: directory)
        let vm = ConnectViewModel(repo: repo, transport: SetupUITestTransport(), encrypt: { "encrypted:\($0)" })
        await authenticate(vm)
        vm.shopName = " My studio "; vm.tintIndex = 2; vm.selectedLanguage = vm.languages.last
        var callbacks: [String] = []
        vm.finish { callbacks.append($0) }
        vm.finish { callbacks.append($0) }
        vm.cancel() // Commit cannot be interrupted after persistence starts.
        await vm.task?.value
        #expect(callbacks.count == 1 && repo.data.shops.count == 1)
        #expect(vm.completed && vm.password.isEmpty && !vm.canContinue)
        let restored = AppRepository(directory: directory)
        await restored.bootstrap()
        let shop = try #require(restored.data.shops.first)
        #expect(shop.name == "My studio" && shop.dailyTarget == nil && shop.tintIndex == 2)
        #expect(shop.localeCode == "de-DE" && shop.currency == "EUR")
        #expect(restored.data.selectedShopId == shop.id && restored.data.onboardingSeen)
        guard case let .admin(username, token, password) = shop.auth else { Issue.record("Expected admin authentication"); return }
        #expect(username == "admin" && token == "encrypted:setup-refresh" && password == "encrypted:fixture-password")
    }

    @Test func encryptionFailureDoesNotCreateShopAndCanRetry() async {
        let repo = AppRepository(directory: FileManager.default.temporaryDirectory.appendingPathComponent("setup-unit-\(UUID())"))
        let encryption = SetupEncryptionFailure()
        let vm = ConnectViewModel(repo: repo, transport: SetupUITestTransport(), encrypt: { value in
            if encryption.shouldFail { throw CocoaError(.fileWriteNoPermission) }
            return "encrypted:\(value)"
        })
        await authenticate(vm)
        vm.finish { _ in Issue.record("Must not complete after encryption failure") }
        await vm.task?.value
        #expect(repo.data.shops.isEmpty && vm.issue != nil && vm.canContinue)
        #expect(vm.password == "fixture-password")
        encryption.shouldFail = false
        vm.finish { _ in }; await vm.task?.value
        #expect(repo.data.shops.count == 1 && vm.completed)
    }

    @Test func canceledProbeIgnoresLateResponse() async {
        let transport = SuspendedSetupProbe()
        let vm = makeModel(transport: transport)
        vm.url = "setup-ui.test"
        vm.submitUrl()
        await transport.waitUntilRequested()
        let original = vm.task
        vm.cancel()
        #expect(!vm.busy && vm.canContinue && vm.issue == nil)
        await transport.resume()
        await original?.value
        #expect(vm.step == .shop && vm.normalizedUrl.isEmpty)
    }

    private func makeModel(transport: any HTTPTransport = SetupUITestTransport()) -> ConnectViewModel {
        ConnectViewModel(repo: AppRepository(directory: FileManager.default.temporaryDirectory.appendingPathComponent("setup-unit-\(UUID())")),
                         transport: transport, encrypt: { "encrypted:\($0)" })
    }

    private func authenticate(_ vm: ConnectViewModel) async {
        vm.url = "setup-ui.test"
        vm.submitUrl(); await vm.task?.value
        vm.username = "admin"; vm.password = "fixture-password"
        vm.signIn(); await vm.task?.value
    }
}

@MainActor
private final class SetupEncryptionFailure {
    var shouldFail = true
}

private actor SuspendedSetupProbe: HTTPTransport {
    private var response: CheckedContinuation<HTTPResponse, Never>?
    private var started: CheckedContinuation<Void, Never>?
    func perform(_ request: HTTPRequest) async throws -> HTTPResponse {
        await withCheckedContinuation { continuation in
            response = continuation
            started?.resume(); started = nil
        }
    }
    func waitUntilRequested() async {
        if response != nil { return }
        await withCheckedContinuation { started = $0 }
    }
    func resume() {
        response?.resume(returning: HTTPResponse(status: 400, body: Data("{\"errors\":[]}".utf8)))
        response = nil
    }
}
