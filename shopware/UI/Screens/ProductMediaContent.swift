import SwiftUI
import ShopwareAdminAPI
import PhotosUI
import UniformTypeIdentifiers

struct ProductMediaContent: View {
    let product: ProductItem
    let actions: ProductActions
    let onSave: () -> Void
    @Environment(\.openURL) private var openURL
    @State private var selecting = false
    @State private var importing = false
    @State private var photo: PhotosPickerItem?
    @State private var removing: ProductMediaItem?
    #if os(iOS)
    @State private var camera = false
    #endif
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(product.media.count) media files").foregroundStyle(.secondary)
                Spacer()
                if !product.isVariant {
                    Menu {
                        Button("Choose from media library…", systemImage: "photo.on.rectangle") { selecting = true }.disabled(!actions.canAddMedia)
                            .accessibilityIdentifier("product.media.choose")
                        Button("Upload file…", systemImage: "square.and.arrow.up") { importing = true }.disabled(!actions.canUpload || actions.pendingMediaID != nil)
                        PhotosPicker(selection: $photo, matching: .images, preferredItemEncoding: .current) { Label("Choose photo", systemImage: "photo") }.disabled(!actions.canUpload || actions.pendingMediaID != nil)
                        #if os(iOS)
                        Button("Take photo", systemImage: "camera") { camera = true }.disabled(!actions.canUpload || actions.pendingMediaID != nil)
                        #endif
                    } label: { Label("Add media", systemImage: "plus") }.accessibilityIdentifier("product.media.add")
                }
            }.padding().fixedSize(horizontal: false, vertical: true)
            if let error = actions.error {
                VStack(alignment: .leading) {
                    Text(error).foregroundStyle(.red)
                    if actions.pendingMediaID != nil {
                        Text("The file was uploaded. Retry adding it to this product.").foregroundStyle(.secondary)
                        Button("Retry") { Task { if await actions.retryMediaAttachment(product) { onSave() } } }.disabled(actions.busy)
                    }
                }.padding().frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("product.media.error")
            }
            if product.isVariant { Text("Manage inherited media on the parent product.").foregroundStyle(.secondary).padding() }
            if product.media.isEmpty {
                ContentUnavailableView { Label("No product media", systemImage: "photo.on.rectangle") }
                description: { Text("Add photos or videos to show customers this product.") }
                actions: { if actions.canAddMedia && !product.isVariant { Button("Choose media…") { selecting = true } } }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 196, maximum: 260), spacing: 16, alignment: .top)], alignment: .leading, spacing: 20) {
                        ForEach(product.media) { item in
                            VStack(alignment: .leading, spacing: 8) {
                                Button { if let url = item.url.flatMap(URL.init(string:)) { openURL(url) } } label: {
                                    ProductThumbnail(url: item.mimeType.hasPrefix("image/") ? item.url : nil, size: 160).frame(maxWidth: .infinity)
                                }.buttonStyle(.plain).accessibilityLabel(item.name.isEmpty ? String(localized: "Open media") : item.name)
                                Text(item.name).lineLimit(2).fontWeight(.medium)
                                if product.coverID == item.id { Label("Cover", systemImage: "checkmark.circle.fill").font(.callout).foregroundStyle(.tint) }
                                if !product.isVariant {
                                    HStack {
                                        Button("Set as cover") { Task { if await actions.setCover(product, media: item) { onSave() } } }
                                            .disabled(!actions.canEdit || product.coverID == item.id).accessibilityIdentifier("product.media.cover." + item.id)
                                        Spacer(minLength: 4)
                                        Button("Remove", systemImage: "trash", role: .destructive) { removing = item }.labelStyle(.iconOnly)
                                            .disabled(!actions.canRemoveMedia).accessibilityIdentifier("product.media.remove." + item.id)
                                    }.buttonStyle(.borderless).font(.callout)
                                }
                            }.padding(12).background(.quaternary.opacity(0.3), in: .rect(cornerRadius: 12))
                        }
                    }.padding(20)
                }
            }
        }
        .sheet(isPresented: $selecting) {
            CustomerEntitySelectionSheet(api: actions.api, entity: "media", title: String(localized: "Choose media"), multiple: true,
                                         selected: [], labelProperty: "fileName", sortField: "fileName",
                                         isEnabled: { entity in !product.media.contains { $0.mediaID == entity.id } },
                                         unavailableMessage: String(localized: "Files already attached to this product are unavailable.")) { ids in
                Task { if await actions.attachMedia(product, mediaIDs: ids) { onSave() } }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.image, .movie, .audio, .pdf]) { result in
            switch result {
            case .success(let url): Task { await uploadFile(url) }
            case .failure(let error): actions.error = error.localizedDescription
            }
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task {
                do {
                    guard let data = try await item.loadTransferable(type: Data.self) else { throw CocoaError(.fileReadUnknown) }
                    let type = item.supportedContentTypes.first ?? .jpeg
                    if await actions.uploadMedia(product, data: data, fileExtension: type.preferredFilenameExtension ?? "jpg", fileName: nil, mimeType: type.preferredMIMEType ?? "image/jpeg") { onSave() }
                } catch { actions.error = error.localizedDescription }
                photo = nil
            }
        }
        #if os(iOS)
        .sheet(isPresented: $camera) {
            CameraPicker { data in
                Task { if await actions.uploadMedia(product, data: data, fileExtension: "jpg", fileName: nil, mimeType: "image/jpeg") { onSave() } }
            }
        }
        #endif
        .confirmationDialog("Remove product media?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            if let item = removing { Button("Remove from product", role: .destructive) { Task { if await actions.removeMedia(product, media: item) { onSave() }; removing = nil } } }
        } message: { Text("The file will remain in the media library.") }
    }
    private func uploadFile(_ url: URL) async {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let type = UTType(filenameExtension: url.pathExtension) ?? .data
            if await actions.uploadMedia(product, data: data, fileExtension: url.pathExtension, fileName: url.deletingPathExtension().lastPathComponent, mimeType: type.preferredMIMEType ?? "application/octet-stream") { onSave() }
        } catch { actions.error = error.localizedDescription }
    }
}
