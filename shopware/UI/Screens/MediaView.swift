import SwiftUI
import ShopwareAdminAPI
import PhotosUI
import Foundation

/// Browses the shop's media library one folder level at a time. Folders and files are fetched on
/// demand per level; navigation is tracked as a stack so the toolbar can offer an up action and the
/// title can reflect the current folder.
@MainActor
@Observable
final class MediaViewModel {
    private let repo: AppRepository
    let shop: ConnectedShop

    private static let pageSize = 50

    private(set) var folders: [MediaFolderItem] = []
    private(set) var files: [MediaItem] = []
    private(set) var fileTotal = 0
    /// Navigation stack of opened folders. The last entry is the current folder; empty means root.
    private(set) var path: [MediaFolderItem] = []
    private(set) var loading = false
    private(set) var loadingMore = false
    private(set) var error: String?
    var searchTerm = ""

    private var page = 1

    init(repo: AppRepository, shop: ConnectedShop) {
        self.repo = repo
        self.shop = shop
    }

    /// Descends into a folder (or returns to root when nil) and reloads its contents.
    func open(_ folder: MediaFolderItem?) async {
        if let folder {
            path.append(folder)
        } else {
            path.removeAll()
        }
        await load()
    }

    /// Pops back to the parent folder and reloads.
    func goUp() async {
        if !path.isEmpty {
            path.removeLast()
        }
        await load()
    }

    func search() async {
        await load()
    }

    private func fileCriteria(page: Int) -> Criteria {
        let criteria = mediaListCriteria(path.last?.id)
            .setPage(page)
            .setLimit(Self.pageSize)
            .setTotalCountMode(.exact)
        let term = searchTerm.trimmingCharacters(in: .whitespaces)
        if !term.isEmpty { criteria.setTerm(term) }
        return criteria
    }

    func load() async {
        loading = true
        error = nil
        page = 1
        let folderId = path.last?.id
        do {
            folders = try await repo.mediaFolders(shop, parentId: folderId)
            let result = try await repo.apiFor(shop).repository("media").search(fileCriteria(page: 1))
            fileTotal = result.total
            files = result.data.map { parseMedia($0, shop.baseUrl) }
        } catch {
            self.error = (error as? ApiError)?.message ?? error.localizedDescription
        }
        loading = false
    }

    func loadMore() async {
        guard !loadingMore, !loading, files.count < fileTotal else { return }
        loadingMore = true
        page += 1
        do {
            let result = try await repo.apiFor(shop).repository("media").search(fileCriteria(page: page))
            files += result.data.map { parseMedia($0, shop.baseUrl) }
        } catch {
            page -= 1
        }
        loadingMore = false
    }

    func createFolder(name: String) async {
        do {
            _ = try await repo.createMediaFolder(shop, parentId: path.last?.id, name: name)
            await load()
        } catch {
            self.error = (error as? ApiError)?.message ?? error.localizedDescription
        }
    }

    func upload(data: Data, ext: String) async {
        do {
            _ = try await repo.uploadMedia(shop, folderId: path.last?.id, bytes: data, extension: ext)
            await load()
        } catch {
            self.error = (error as? ApiError)?.message ?? error.localizedDescription
        }
    }

    func delete(_ item: MediaItem) async {
        do {
            try await repo.deleteMedia(shop, mediaId: item.id)
            await load()
        } catch {
            self.error = (error as? ApiError)?.message ?? error.localizedDescription
        }
    }
}

/// A grid-based media browser: folders first, then file thumbnails. Supports creating folders,
/// uploading images via the photo picker, and inspecting/deleting a file in a detail sheet.
struct MediaView: View {
    @Environment(AppViewModel.self) private var model
    let shop: ConnectedShop

    @State private var vm: MediaViewModel?
    @State private var showingNewFolder = false
    @State private var newFolderName = ""
    @State private var selectedItem: MediaItem?
    @State private var photoItem: PhotosPickerItem?
    @State private var searchText = ""
    #if os(iOS)
    @State private var showingCamera = false
    #endif

    private let columns = [GridItem(.adaptive(minimum: 100), spacing: 12)]

    var body: some View {
        Group {
            if let vm {
                content(vm)
            } else {
                ProgressView()
            }
        }
        .navigationTitle(vm?.path.last?.name ?? "Media")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .searchable(text: $searchText, prompt: "Search files")
        .onSubmit(of: .search) {
            vm?.searchTerm = searchText
            Task { await vm?.search() }
        }
        .onChange(of: searchText) { _, new in
            if new.isEmpty, vm?.searchTerm.isEmpty == false {
                vm?.searchTerm = ""
                Task { await vm?.search() }
            }
        }
        .toolbar {
            if let vm, !vm.path.isEmpty {
                ToolbarItem(placement: .navigation) {
                    Button { Task { await vm.goUp() } } label: { Image(systemName: "chevron.backward") }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showingNewFolder = true } label: { Image(systemName: "folder.badge.plus") }
            }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Choose photo", systemImage: "photo")
                    }
                    #if os(iOS)
                    Button { showingCamera = true } label: { Label("Take photo", systemImage: "camera") }
                    #endif
                } label: {
                    Label("Upload", systemImage: "photo.badge.plus")
                }
            }
        }
        #if os(iOS)
        .sheet(isPresented: $showingCamera) {
            CameraPicker { data in
                Task { await vm?.upload(data: data, ext: "jpg") }
            }
            .ignoresSafeArea()
        }
        #endif
        .alert("New folder", isPresented: $showingNewFolder) {
            TextField("Name", text: $newFolderName)
            Button("Cancel", role: .cancel) { newFolderName = "" }
            Button("Create") {
                let name = newFolderName.trimmingCharacters(in: .whitespacesAndNewlines)
                newFolderName = ""
                guard !name.isEmpty else { return }
                Task { await vm?.createFolder(name: name) }
            }
        }
        .sheet(item: $selectedItem) { item in
            MediaDetailSheet(item: item) {
                await vm?.delete(item)
            }
        }
        .onChange(of: photoItem) { _, item in
            Task {
                if let data = try? await item?.loadTransferable(type: Data.self) {
                    await vm?.upload(data: data, ext: "jpg")
                }
                photoItem = nil
            }
        }
        .task {
            if vm == nil { vm = MediaViewModel(repo: model.repo, shop: shop) }
            await vm?.load()
        }
    }

    private func content(_ vm: MediaViewModel) -> some View {
        ScrollView {
            if let error = vm.error {
                ContentUnavailableView("Couldn't load", systemImage: "exclamationmark.triangle", description: Text(error))
                    .padding()
            } else {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(vm.folders) { folder in
                        Button { Task { await vm.open(folder) } } label: {
                            folderCell(folder)
                        }
                        .buttonStyle(.plain)
                    }
                    ForEach(vm.files) { file in
                        Button { selectedItem = file } label: {
                            fileCell(file)
                        }
                        .buttonStyle(.plain)
                        .onAppear {
                            if file.id == vm.files.last?.id { Task { await vm.loadMore() } }
                        }
                    }
                }
                .padding()
                if vm.loadingMore {
                    ProgressView().padding()
                }
            }
        }
    }

    private func folderCell(_ folder: MediaFolderItem) -> some View {
        VStack(spacing: 6) {
            Image(systemName: "folder.fill")
                .font(.system(size: 40))
                .foregroundStyle(Theme.accent)
                .frame(height: 80)
            Text(folder.name)
                .font(.caption)
                .lineLimit(1)
            Text("\(folder.childCount)")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func fileCell(_ file: MediaItem) -> some View {
        VStack(spacing: 6) {
            if file.isImage, let url = URL(string: file.url ?? "") {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    ProgressView()
                }
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                Image(systemName: "doc")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                    .frame(height: 80)
            }
            Text(file.fileName)
                .font(.caption)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Shows a single file's preview and metadata with a destructive delete action.
private struct MediaDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    let item: MediaItem
    let onDelete: () async -> Void

    @State private var deleting = false

    private var sizeText: String {
        ByteCountFormatter.string(fromByteCount: item.fileSize, countStyle: .file)
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    if item.isImage, let url = URL(string: item.url ?? "") {
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFit()
                        } placeholder: {
                            ProgressView()
                        }
                        .frame(maxWidth: .infinity, minHeight: 200)
                    } else {
                        Image(systemName: "doc")
                            .font(.system(size: 60))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, minHeight: 200)
                    }
                }
                .listRowBackground(Color.clear)

                Section {
                    LabeledContent("Name", value: item.fileName)
                    LabeledContent("Type", value: item.fileExtension)
                    LabeledContent("Size", value: sizeText)
                    LabeledContent("Uploaded", value: relativeAgoText(item.uploadedMs))
                }

                Section {
                    Button(role: .destructive) {
                        Task {
                            deleting = true
                            await onDelete()
                            dismiss()
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .disabled(deleting)
                }
            }
            .navigationTitle(item.fileName)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
        .acceptsFirstMouse()
    }
}
