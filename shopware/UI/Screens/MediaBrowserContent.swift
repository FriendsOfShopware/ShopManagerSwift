import SwiftUI
import ShopwareAdminAPI

struct MediaBrowserContent: View {
    @Bindable var vm: MediaViewModel
    let presentation: String
    let selecting: Bool
    let inspectedID: String?
    let openFile: (MediaItem) -> Void
    let editFolder: (MediaFolderItem) -> Void
    let deleteFiles: (Set<String>) -> Void
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if presentation == "grid" { grid }
            else {
                #if os(macOS)
                table
                #else
                list
                #endif
            }
        }.disabled(vm.busy).accessibilityIdentifier(presentation == "grid" ? "media.grid" : "media.list")
    }

    private var grid: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !vm.folders.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Folders").font(.headline)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 280 : 160), spacing: 16)], spacing: 12) {
                            ForEach(vm.folders) { folder in folderButton(folder).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 10)) }
                        }
                    }
                }
                if !vm.files.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Files").font(.headline)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: typeSize.isAccessibilitySize ? 240 : 150), spacing: 16)], spacing: 20) {
                            ForEach(vm.files) { item in
                                Button { openFile(item) } label: {
                                    VStack(alignment: .leading, spacing: 7) {
                                        MediaThumbnail(item: item).frame(height: 132)
                                            .overlay(alignment: .topTrailing) {
                                                if selecting { Image(systemName: vm.selection.contains(item.id) ? "checkmark.circle.fill" : "circle")
                                                        .font(.body).foregroundStyle(vm.selection.contains(item.id) ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
                                                        .padding(5).background(.background, in: .circle).padding(6) }
                                            }
                                        Text(item.displayName).font(.callout.weight(.medium)).foregroundStyle(.primary).lineLimit(2, reservesSpace: true)
                                        Text(item.sizeText).font(.caption).foregroundStyle(.secondary)
                                    }.padding(8).frame(maxWidth: .infinity, alignment: .leading)
                                        .background(vm.selection.contains(item.id) || inspectedID == item.id ? Color.accentColor.opacity(0.12) : .clear, in: .rect(cornerRadius: 12))
                                        .contentShape(.rect)
                                }.buttonStyle(.plain).accessibilityIdentifier("media.file.\(item.id)")
                                    .accessibilityAddTraits(vm.selection.contains(item.id) ? [.isSelected] : [])
                                    .contextMenu { fileMenu(item) }
                            }
                        }
                    }
                }
            }.padding(20)
        }.refreshable { await vm.load() }
    }

    #if os(iOS)
    private var list: some View {
        List {
            if !vm.folders.isEmpty { Section("Folders") { ForEach(vm.folders) { folderButton($0) } } }
            if !vm.files.isEmpty {
                Section("Files") {
                    ForEach(vm.files) { item in
                        Button { openFile(item) } label: {
                            HStack {
                                if selecting { Image(systemName: vm.selection.contains(item.id) ? "checkmark.circle.fill" : "circle") }
                                MediaFileRow(item: item)
                            }
                        }.buttonStyle(.plain).accessibilityIdentifier("media.file.\(item.id)")
                            .accessibilityAddTraits(vm.selection.contains(item.id) ? [.isSelected] : [])
                            .contextMenu { fileMenu(item) }
                    }
                }
            }
        }.listStyle(.insetGrouped).refreshable { await vm.load() }
    }
    #else
    private var table: some View {
        Table(rows) {
            TableColumn("Name") { row in
                if let folder = row.folder { folderButton(folder) }
                else if let item = row.file {
                    Button { openFile(item) } label: {
                        HStack {
                            if selecting { Image(systemName: vm.selection.contains(item.id) ? "checkmark.circle.fill" : "circle") }
                            MediaThumbnail(item: item).frame(width: 28, height: 28)
                            Text(item.displayName).lineLimit(1).foregroundStyle(.primary)
                            Spacer(minLength: 0)
                        }
                        .contentShape(.rect)
                    }.buttonStyle(.plain).accessibilityIdentifier("media.file.\(item.id)").contextMenu { fileMenu(item) }
                }
            }.width(min: 220, ideal: 340)
            TableColumn("Kind") { row in Text(row.file?.fileExtension.uppercased() ?? String(localized: "Folder")).foregroundStyle(.secondary) }.width(min: 60, ideal: 80)
            TableColumn("Size") { row in Text(row.file?.sizeText ?? "—").monospacedDigit().foregroundStyle(.secondary) }.width(min: 70, ideal: 90)
            TableColumn("Uploaded") { row in
                if let file = row.file, file.uploadedMs > 0 { Text(Date(timeIntervalSince1970: Double(file.uploadedMs) / 1000), format: .dateTime.day().month().year()).foregroundStyle(.secondary) }
                else { Text("—").foregroundStyle(.secondary) }
            }.width(min: 90, ideal: 120)
        }
    }
    private var rows: [MediaTableRow] { vm.folders.map { MediaTableRow(folder: $0) } + vm.files.map { MediaTableRow(file: $0) } }
    #endif

    private func folderButton(_ folder: MediaFolderItem) -> some View {
        Button { Task { await vm.open(folder) } } label: { MediaFolderLabel(folder: folder).frame(maxWidth: .infinity, alignment: .leading).contentShape(.rect) }
            .buttonStyle(.plain).accessibilityIdentifier("media.folder.\(folder.id)")
            .contextMenu {
                Button("Open folder", systemImage: "folder") { Task { await vm.open(folder) } }
                Button("Rename folder…", systemImage: "pencil") { editFolder(folder) }
                    .disabled(!vm.permissions.allows("media_folder:update"))
            }
    }
    @ViewBuilder private func fileMenu(_ item: MediaItem) -> some View {
        Button(selecting ? "Toggle selection" : "Get info", systemImage: selecting ? "checkmark.circle" : "info.circle") { openFile(item) }
        if let url = URL(string: item.url ?? "") { ShareLink(item: url) }
        Button("Delete", systemImage: "trash", role: .destructive) { deleteFiles([item.id]) }.disabled(!vm.canDelete)
    }
}

#if os(macOS)
private struct MediaTableRow: Identifiable {
    var folder: MediaFolderItem?
    var file: MediaItem?
    var id: String { folder.map { "folder-" + $0.id } ?? "file-" + (file?.id ?? "") }
}
#endif
