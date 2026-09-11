import Foundation
import Observation
import ShopwareAdminAPI
import UniformTypeIdentifiers

@MainActor
@Observable
final class MediaViewModel {
    let api: ShopApi
    let shop: ConnectedShop
    private(set) var folders: [MediaFolderItem] = []
    private(set) var files: [MediaItem] = []
    private(set) var fileTotal = 0
    private(set) var path: [MediaFolderItem] = []
    private(set) var loading = false
    private(set) var loadingMore = false
    private(set) var busy = false
    private(set) var error: String?
    private(set) var permissions = AdminPermissions()
    private(set) var permissionsError: String?
    private(set) var uploadProgress = 0
    private(set) var uploadCount = 0
    var actionError: String?
    var selection = Set<String>()
    var searchTerm = ""
    var sort = MediaSort.newest
    var kind = MediaKind.all
    private var page = 1
    private var requestID = 0

    init(repo: AppRepository, shop: ConnectedShop) {
        self.api = repo.apiFor(shop)
        self.shop = shop
    }

    var folderId: String? { path.last?.id }
    var selectedFiles: [MediaItem] { files.filter { selection.contains($0.id) } }
    var canUpload: Bool { permissions.allows("media:create") && permissions.allows("media:update") && !busy }
    var canEdit: Bool { permissions.allows("media:update") && !busy }
    var canDelete: Bool { permissions.allows("media:delete") && !busy }

    func start() async {
        async let content: Void = load()
        await loadPermissions()
        await content
    }

    func loadPermissions() async {
        do { permissions = try await api.permissions(); permissionsError = nil }
        catch {
            permissions = AdminPermissions()
            permissionsError = String(localized: "Couldn't load permissions. Retry to enable media actions.")
        }
    }

    func open(_ folder: MediaFolderItem) async {
        guard !busy, folder.id != folderId else { return }
        path.append(folder)
        await changedFolder()
    }

    func navigate(to depth: Int) async {
        guard !busy else { return }
        path = Array(path.prefix(max(0, depth)))
        await changedFolder()
    }

    private func changedFolder() async {
        searchTerm = ""
        selection.removeAll()
        files = []; folders = []; fileTotal = 0
        await load()
    }

    func fetchFolders(parentId: String?, term: String = "") async throws -> [MediaFolderItem] {
        var all: [MediaFolderItem] = []
        var seen = Set<String>()
        var nextPage = 1
        while true {
            try Task.checkCancellation()
            let result = try await api.repository("media-folder").search(mediaFolderCriteria(parentId, page: nextPage, term: term))
            all += result.data.map(parseMediaFolder).filter { seen.insert($0.id).inserted }
            if result.data.isEmpty || all.count >= result.total { return all }
            nextPage += 1
        }
    }

    private func criteria(page: Int) -> Criteria {
        let criteria = mediaListCriteria(folderId, sort: sort, kind: kind)
            .setPage(page).setLimit(50).setTotalCountMode(.exact)
        let term = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
        if !term.isEmpty { criteria.setTerm(term) }
        return criteria
    }

    func load(preserveLoadedPages: Bool = false) async {
        requestID += 1
        let request = requestID
        let pagesToLoad = preserveLoadedPages ? page : 1
        loading = true; loadingMore = false; error = nil
        defer { if request == requestID { loading = false } }
        do {
            let folder = folderId
            let query = criteria(page: 1)
            let term = searchTerm.trimmingCharacters(in: .whitespacesAndNewlines)
            async let newFolders = fetchFolders(parentId: folder, term: term)
            async let result = fetchFiles(query, throughPage: pagesToLoad)
            let (loadedFolders, loadedFiles) = try await (newFolders, result)
            guard request == requestID else { return }
            folders = loadedFolders
            files = loadedFiles.data.map { parseMedia($0, shop.baseUrl) }
            fileTotal = loadedFiles.total; page = loadedFiles.page
            selection.formIntersection(Set(files.map(\.id)))
        } catch is CancellationError { }
        catch { if request == requestID { self.error = message(error) } }
    }

    private func fetchFiles(_ query: Criteria, throughPage lastPage: Int) async throws -> (data: [SwEntity], total: Int, page: Int) {
        var data: [SwEntity] = []
        var seen = Set<String>()
        var total = 0
        var loadedPage = 0
        for next in 1...lastPage {
            try Task.checkCancellation()
            let result = try await api.repository("media").search(query.setPage(next))
            data += result.data.filter { entity in
                guard let id = entity.id else { return false }
                return seen.insert(id).inserted
            }
            total = result.total; loadedPage = next
            if result.data.isEmpty || data.count >= total { break }
        }
        return (data, total, loadedPage)
    }

    func loadMore() async {
        guard !loading, !loadingMore, files.count < fileTotal else { return }
        let request = requestID
        loadingMore = true
        defer { if request == requestID { loadingMore = false } }
        do {
            let result = try await api.repository("media").search(criteria(page: page + 1))
            guard request == requestID else { return }
            let existing = Set(files.map(\.id))
            files += result.data.map { parseMedia($0, shop.baseUrl) }.filter { !existing.contains($0.id) }
            fileTotal = result.total; page += 1; actionError = nil
        } catch { if request == requestID { actionError = message(error) } }
    }

    func saveFolder(name: String, folder: MediaFolderItem?) async -> Bool {
        guard !busy, permissions.allows(folder == nil ? "media_folder:create" : "media_folder:update") else { return false }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return false }
        busy = true; actionError = nil
        defer { busy = false }
        do {
            if let folder { try await api.repository("media-folder").patch(folder.id, .object(["name": .string(name)])) }
            else { try await api.media.createFolder(name: name, parentId: folderId) }
            await load(preserveLoadedPages: true)
            return true
        } catch { actionError = message(error); return false }
    }

    func saveDetails(item: MediaItem, fileName: String, title: String, alt: String) async -> Bool {
        guard canEdit else { return false }
        busy = true; actionError = nil
        defer { busy = false }
        do {
            // Metadata is saved before renaming; a failed rename can be retried with this draft.
            try await api.repository("media").patch(item.id, .object(["title": .string(title), "alt": .string(alt)]))
            if fileName != item.fileName { try await api.media.rename(item.id, fileName: fileName) }
            await load(preserveLoadedPages: true)
            return true
        } catch { actionError = message(error); return false }
    }

    func delete(_ ids: Set<String>) async -> Bool {
        guard canDelete, !ids.isEmpty else { return false }
        return await mutateFiles(ids) { try await self.api.repository("media").delete($0) }
    }

    func move(_ ids: Set<String>, to folderId: String?) async -> Bool {
        guard canEdit, !ids.isEmpty else { return false }
        return await mutateFiles(ids) {
            try await self.api.repository("media").patch($0, .object(["mediaFolderId": folderId.map(JSONValue.string) ?? .null]))
        }
    }

    private func mutateFiles(_ ids: Set<String>, action: (String) async throws -> Void) async -> Bool {
        busy = true; actionError = nil
        defer { busy = false }
        var failed = Set<String>()
        var failure: String?
        for id in ids.sorted() {
            do { try await action(id) }
            catch { failed.insert(id); failure = message(error) }
        }
        selection = failed
        await load(preserveLoadedPages: true)
        if let failure { actionError = String(localized: "\(failed.count) files could not be updated.") + " " + failure }
        return failed.isEmpty
    }

    func uploadFiles(_ urls: [URL]) async {
        guard canUpload, !urls.isEmpty else { return }
        let destination = folderId
        busy = true; actionError = nil; uploadProgress = 0; uploadCount = urls.count
        defer { busy = false; uploadCount = 0 }
        var failures: [String] = []
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            do {
                guard !url.pathExtension.isEmpty else { throw CocoaError(.fileReadUnknown) }
                let data = try await Task.detached { try Data(contentsOf: url) }.value
                try await api.media.upload(bytes: data, extension: url.pathExtension.lowercased(),
                                           fileName: url.deletingPathExtension().lastPathComponent,
                                           mimeType: UTType(filenameExtension: url.pathExtension)?.preferredMIMEType ?? "application/octet-stream",
                                           mediaFolderId: destination)
            } catch { failures.append(url.lastPathComponent + ": " + message(error)) }
            uploadProgress += 1
        }
        await load(preserveLoadedPages: true)
        if !failures.isEmpty { actionError = failures.joined(separator: "\n") }
    }

    func uploadPhoto(data: Data, type: UTType) async {
        guard canUpload else { return }
        busy = true; actionError = nil; uploadProgress = 0; uploadCount = 1
        defer { busy = false; uploadCount = 0 }
        do {
            try await api.media.upload(bytes: data, extension: type.preferredFilenameExtension ?? "jpg", fileName: nil,
                                       mimeType: type.preferredMIMEType ?? "image/jpeg", mediaFolderId: folderId)
            await load(preserveLoadedPages: true)
        } catch { actionError = message(error) }
    }

    private func message(_ error: Error) -> String { (error as? ApiError)?.message ?? error.localizedDescription }
}
