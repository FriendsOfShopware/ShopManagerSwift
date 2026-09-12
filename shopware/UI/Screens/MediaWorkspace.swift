import SwiftUI
import ShopwareAdminAPI
import PhotosUI
import UniformTypeIdentifiers
import ImageIO

struct MediaWorkspace: View {
    @Bindable var vm: MediaViewModel
    @AppStorage("media.presentation") private var presentation = "grid"
    @State private var selecting = false
    @State private var inspector = false
    @State private var inspectedID: String?
    @State private var sheet: MediaBrowserSheet?
    @State private var deleteIDs = Set<String>()
    @State private var importing = false
    @State private var photo: PhotosPickerItem?
    @State private var preparingPhoto = false
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 0) {
            breadcrumbs.fixedSize(horizontal: false, vertical: true)
            if let error = vm.permissionsError {
                HStack { Text(error); Button("Retry") { Task { await vm.loadPermissions() } } }
                    .font(.callout).foregroundStyle(.secondary).padding()
            }
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
            footer.fixedSize(horizontal: false, vertical: true)
        }
        .task(id: vm.searchTerm) {
            // Debounce typing; the model rejects responses from superseded searches.
            do { try await Task.sleep(for: .milliseconds(300)); await vm.load() }
            catch { }
        }
        .onChange(of: vm.sort) { Task { await vm.load() } }
        .onChange(of: vm.kind) { Task { await vm.load() } }
        .onChange(of: vm.folderId) { inspector = false; inspectedID = nil; selecting = false }
        // Keep the selected file while the system moves the inspector between overlay and column.
        // iPad rotation can temporarily dismiss the presentation during that transition.
        .onChange(of: vm.files.map(\.id)) {
            if let inspectedID, !vm.files.contains(where: { $0.id == inspectedID }) { inspector = false; self.inspectedID = nil }
        }
        .modifier(MediaInspectorPresentation(vm: vm, itemID: inspectedID, isPresented: $inspector))
        .navigationTitle(vm.path.last?.name ?? String(localized: "Media"))
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .searchable(text: $vm.searchTerm, prompt: "Search this folder")
        .toolbar { browserToolbar }
        .sheet(item: $sheet) { destination in
            Group {
                switch destination {
                case .folder(let folder): MediaFolderEditor(vm: vm, folder: folder)
                case .move(let ids): MediaMoveSheet(vm: vm, ids: ids)
                #if os(iOS)
                case .camera: CameraPicker { data in Task { await vm.uploadPhoto(data: data, type: .jpeg) } }
                #endif
                }
            }.dynamicTypeSize(typeSize)
        }
        .alert("Delete \(deleteIDs.count) files?", isPresented: Binding(get: { !deleteIDs.isEmpty }, set: { if !$0 { deleteIDs = [] } })) {
            Button("Cancel", role: .cancel) { deleteIDs = [] }
            Button("Delete", role: .destructive) {
                let ids = deleteIDs; deleteIDs = []
                Task { if await vm.delete(ids) { inspector = false } }
            }.accessibilityIdentifier("media.delete.confirm")
        } message: { Text("These files will be permanently deleted, including where they are used in your shop.") }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.data], allowsMultipleSelection: true) { result in
            switch result {
            case .success(let urls): Task { await vm.uploadFiles(urls) }
            case .failure(let error): vm.actionError = error.localizedDescription
            }
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            preparingPhoto = true
            Task {
                defer { preparingPhoto = false; photo = nil }
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { return }
                    let source = CGImageSourceCreateWithData(data as CFData, nil)
                    let type = source.flatMap { CGImageSourceGetType($0) }.flatMap { UTType($0 as String) } ?? .jpeg
                    await vm.uploadPhoto(data: data, type: type)
                } catch { vm.actionError = error.localizedDescription }
            }
        }
    }

    private var breadcrumbs: some View {
        HStack(spacing: 12) {
            if !vm.path.isEmpty {
                Button { Task { await vm.navigate(to: vm.path.count - 1) } } label: {
                    Label("Parent folder", systemImage: "arrow.up")
                }.labelStyle(.iconOnly).help("Parent folder").accessibilityIdentifier("media.parent")
            }
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    Button("Media library") { Task { await vm.navigate(to: 0) } }
                        .accessibilityIdentifier("media.root")
                    ForEach(vm.path) { folder in
                        Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary)
                        Button(folder.name) {
                            if let index = vm.path.firstIndex(where: { $0.id == folder.id }) {
                                Task { await vm.navigate(to: index + 1) }
                            }
                        }
                    }
                }.lineLimit(1)
            }.scrollIndicators(.hidden)
            if vm.loading && !vm.files.isEmpty { ProgressView().controlSize(.small) }
        }
        .buttonStyle(.plain).font(.callout).foregroundStyle(.secondary)
        .padding(.horizontal, 20).padding(.vertical, 12).disabled(vm.busy)
        .overlay(alignment: .bottom) { Divider() }
    }

    @ViewBuilder private var content: some View {
        if vm.loading && vm.files.isEmpty && vm.folders.isEmpty {
            ProgressView("Loading media…").frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = vm.error {
            ContentUnavailableView {
                Label("Couldn't load media", systemImage: "exclamationmark.triangle")
            } description: { Text(error) } actions: { Button("Retry") { Task { await vm.load() } } }
        } else if vm.files.isEmpty && vm.folders.isEmpty {
            ContentUnavailableView {
                Label(filtered ? "No matching files" : "This folder is empty", systemImage: filtered ? "magnifyingglass" : "photo.on.rectangle.angled")
            } description: {
                Text(filtered ? "Try another search or file type." : "Upload images, videos, or documents to use in your shop.")
            } actions: {
                if filtered { Button("Clear filters") { vm.searchTerm = ""; vm.kind = .all } }
                else { Button("Upload files…") { importing = true }.disabled(!vm.canUpload) }
            }
        } else {
            MediaBrowserContent(vm: vm, presentation: presentation, selecting: selecting, inspectedID: inspectedID,
                                openFile: inspect, editFolder: { sheet = .folder($0) }, deleteFiles: { deleteIDs = $0 })
        }
    }

    private var filtered: Bool { !vm.searchTerm.isEmpty || vm.kind != .all }

    @ToolbarContentBuilder private var browserToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                Button("Choose files…", systemImage: "folder") { importing = true }
                PhotosPicker(selection: $photo, matching: .images, preferredItemEncoding: .current) {
                    Label("Photo library…", systemImage: "photo")
                }
                #if os(iOS)
                Button("Take photo…", systemImage: "camera") { sheet = .camera }
                    .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                #endif
            } label: { Label("Upload", systemImage: "plus") }
                .disabled(!vm.canUpload || preparingPhoto).help("Upload files")
                .accessibilityIdentifier("media.upload")
            Menu {
                Picker("View", selection: $presentation) {
                    Label("Grid", systemImage: "square.grid.2x2").tag("grid")
                    Label("List", systemImage: "list.bullet").tag("list")
                }
                Picker("Sort by", selection: $vm.sort) { ForEach(MediaSort.allCases) { Text($0.title).tag($0) } }
                Picker("File type", selection: $vm.kind) { ForEach(MediaKind.allCases) { Text($0.title).tag($0) } }
                Divider()
                Button(selecting ? "Done selecting" : "Select files", systemImage: "checkmark.circle") {
                    selecting.toggle(); vm.selection = []; inspector = false; inspectedID = nil
                }.disabled(vm.files.isEmpty || vm.busy).accessibilityIdentifier("media.select")
                Button("New folder…", systemImage: "folder.badge.plus") { sheet = .folder(nil) }
                    .disabled(!vm.permissions.allows("media_folder:create") || vm.busy)
                Button("Refresh", systemImage: "arrow.clockwise") { Task { await vm.load() } }.disabled(vm.loading || vm.busy)
            } label: { Label("Media options", systemImage: "ellipsis.circle") }
                .accessibilityIdentifier("media.options").help("Media options")
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if let error = vm.actionError {
                HStack(alignment: .top) {
                    Text(error).foregroundStyle(.red).textSelection(.enabled).lineLimit(4)
                    Spacer()
                    Button("Dismiss error", systemImage: "xmark") { vm.actionError = nil }.labelStyle(.iconOnly)
                }.font(.callout)
            }
            HStack(spacing: 16) {
                if vm.uploadCount > 0 {
                    ProgressView(value: Double(vm.uploadProgress), total: Double(vm.uploadCount)).frame(maxWidth: 120)
                    Text("Uploading \(vm.uploadProgress) of \(vm.uploadCount)…")
                } else if preparingPhoto { ProgressView(); Text("Preparing photo…") }
                else if selecting || !vm.selection.isEmpty {
                    if typeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 12) {
                            selectionCount
                            HStack(spacing: 24) { selectionActions }.labelStyle(.iconOnly)
                        }.frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        selectionCount
                        Spacer()
                        selectionActions
                    }
                } else {
                    Text("\(vm.fileTotal) files").accessibilityIdentifier("media.fileCount")
                    Spacer()
                    Text(vm.kind == .all ? vm.sort.title : vm.kind.title).foregroundStyle(.secondary)
                }
            }.font(.callout)
            if vm.files.count < vm.fileTotal && !vm.loading {
                Button("Load more files") { Task { await vm.loadMore() } }.disabled(vm.loadingMore)
                if vm.loadingMore { ProgressView().controlSize(.small) }
            }
        }.padding(.horizontal, 20).padding(.vertical, 12).overlay(alignment: .top) { Divider() }
    }

    private var selectionCount: some View {
        Text("\(vm.selection.count) selected").accessibilityIdentifier("media.selectionCount")
    }
    @ViewBuilder private var selectionActions: some View {
        Button("Move…", systemImage: "folder") { sheet = .move(vm.selection) }
            .disabled(vm.selection.isEmpty || !vm.canEdit).accessibilityIdentifier("media.move")
        Button("Delete", systemImage: "trash", role: .destructive) { deleteIDs = vm.selection }
            .disabled(vm.selection.isEmpty || !vm.canDelete).accessibilityIdentifier("media.delete")
    }

    private func inspect(_ item: MediaItem) {
        if selecting {
            if !vm.selection.insert(item.id).inserted { vm.selection.remove(item.id) }
        } else { inspectedID = item.id; inspector = true }
    }
}

enum MediaBrowserSheet: Identifiable {
    case folder(MediaFolderItem?), move(Set<String>)
    #if os(iOS)
    case camera
    #endif
    var id: String {
        switch self {
        case .folder(let folder): "folder-" + (folder?.id ?? "new")
        case .move: "move"
        #if os(iOS)
        case .camera: "camera"
        #endif
        }
    }
}
