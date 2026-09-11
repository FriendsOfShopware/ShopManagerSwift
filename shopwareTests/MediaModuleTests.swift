import Foundation
import Testing
import ShopwareAdminAPI
@testable import shopware

@MainActor
struct MediaModuleTests {
    private func model(_ transport: MediaUITestTransport) -> MediaViewModel {
        let shop = ConnectedShop(id: "test", name: "Test", baseUrl: "https://media-ui.test")
        let repo = AppRepository(directory: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString), apiFactory: { shop in
            ShopApi(baseURL: shop.baseUrl, auth: .refreshToken(token: "fixture"), transport: transport)
        })
        return MediaViewModel(repo: repo, shop: shop)
    }

    @Test func parsingChoosesAppropriateThumbnailAndTranslatedMetadata() {
        let item = parseMedia(SwEntity(.object([
            "id": "media", "fileName": "linen", "fileExtension": "png", "mimeType": "image/png", "title": "Fallback",
            "translated": .object(["title": "Leinen", "alt": "Hemd"]), "mediaFolderId": "folder",
            "metaData": .object(["width": 1600, "height": 1200]),
            "thumbnails": .array([.object(["width": 800, "url": "https://internal.test/800.png"]),
                                  .object(["width": 200, "url": "https://internal.test/200.png"]),
                                  .object(["width": 400, "url": "https://internal.test/400.png"])])
        ])), "https://media-ui.test")
        #expect(item.displayName == "linen.png")
        #expect(item.title == "Leinen" && item.alt == "Hemd")
        #expect(item.width == 1600 && item.height == 1200)
        #expect(item.thumbnailURL == "https://media-ui.test/400.png")
        #expect(item.folderId == "folder")
    }

    @Test func folderPaginationAndMediaRetryDoNotLoseFiles() async {
        let vm = model(MediaUITestTransport(arguments: ["--fail-page-once"], extraFiles: 60, extraFolders: 110))
        await vm.start()
        #expect(vm.folders.count == 112)
        #expect(vm.files.count == 50 && vm.fileTotal == 66)
        await vm.loadMore()
        #expect(vm.files.count == 50 && vm.actionError != nil)
        await vm.loadMore()
        #expect(vm.files.count == 66 && Set(vm.files.map(\.id)).count == 66)
    }

    @Test func olderSearchResponseCannotOverwriteNewerResults() async throws {
        let transport = MediaUITestTransport()
        let vm = model(transport)
        await vm.start()
        vm.searchTerm = "slow"
        let old = Task { await vm.load() }
        for _ in 0..<1000 {
            if await transport.slowSearchStarted { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        #expect(await transport.slowSearchStarted)
        vm.searchTerm = "linen"
        await vm.load()
        await old.value
        #expect(vm.files.map(\.id) == ["image-1"])
        #expect(!vm.loading)
    }

    @Test func partialDeleteRetainsOnlyFailedSelectionForRetry() async {
        let vm = model(MediaUITestTransport(arguments: ["--fail-delete-once"], extraFiles: 60))
        vm.sort = .oldest
        await vm.start()
        await vm.loadMore()
        #expect(vm.files.firstIndex { $0.id == "image-2" } ?? 0 >= 50)
        #expect(!(await vm.delete(["image-1", "image-2"])))
        #expect(!vm.files.contains { $0.id == "image-1" })
        #expect(vm.files.contains { $0.id == "image-2" })
        #expect(vm.selection == ["image-2"] && vm.actionError != nil)
        #expect(await vm.delete(vm.selection))
        #expect(vm.selection.isEmpty && vm.actionError == nil)
    }

    @Test func metadataFailureAndMoveKeepCorrectFolderState() async throws {
        let vm = model(MediaUITestTransport(arguments: ["--fail-save-once"]))
        await vm.start()
        let item = try #require(vm.files.first { $0.id == "image-1" })
        #expect(!(await vm.saveDetails(item: item, fileName: "linen-renamed", title: "New title", alt: "A shirt")))
        #expect(vm.files.first { $0.id == item.id }?.fileName == item.fileName)
        #expect(await vm.saveDetails(item: item, fileName: "linen-renamed", title: "New title", alt: "A shirt"))
        #expect(await vm.move([item.id], to: "products"))
        #expect(!vm.files.contains { $0.id == item.id })
        let destination = try #require(vm.folders.first { $0.id == "products" })
        await vm.open(destination)
        await vm.open(destination)
        #expect(vm.path.map(\.id) == ["products"])
        #expect(vm.files.first?.fileName == "linen-renamed")
        #expect(vm.files.first?.title == "New title")
        #expect(vm.folders.map(\.id) == ["summer"])
        await vm.navigate(to: 0)
        #expect(vm.path.isEmpty && vm.files.count == 5)
    }

    @Test func filteringSortingAndReadOnlyPermissionsMatchBrowserControls() async {
        let transport = MediaUITestTransport(arguments: ["--read-only"])
        let vm = model(transport)
        await vm.start()
        vm.kind = .images; vm.sort = .largest
        await vm.load()
        #expect(vm.files.map(\.id) == ["image-3", "image-2", "image-1"])
        #expect(!vm.canUpload && !vm.canEdit && !vm.canDelete)
        #expect(!(await vm.delete(["image-1"])))
        #expect(!(await vm.saveFolder(name: "Denied", folder: nil)))
        #expect(await transport.requests.allSatisfy { $0.method == .post || $0.method == .get })
    }
}
