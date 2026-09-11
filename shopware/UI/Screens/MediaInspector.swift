import SwiftUI

/// Compact layouts use a standard sheet so edit/move sheets are presented above the details.
struct MediaInspectorPresentation: ViewModifier {
    let vm: MediaViewModel
    let itemID: String?
    @Binding var isPresented: Bool
    @Environment(\.dynamicTypeSize) private var typeSize
    #if os(iOS)
    @Environment(\.horizontalSizeClass) private var sizeClass
    #endif

    func body(content: Content) -> some View {
        #if os(macOS)
        content.inspector(isPresented: $isPresented) { details }
        #else
        if sizeClass == .compact || typeSize.isAccessibilitySize {
            content.sheet(isPresented: $isPresented) { details.presentationDetents([.large]) }
        } else {
            content.inspector(isPresented: $isPresented) { details }
        }
        #endif
    }

    @ViewBuilder private var details: some View {
        if let item = vm.files.first(where: { $0.id == itemID }) {
            MediaInspector(vm: vm, item: item) { isPresented = false }
                .dynamicTypeSize(typeSize)
                .inspectorColumnWidth(min: 280, ideal: 320, max: 400)
        }
    }
}

struct MediaInspector: View {
    @Bindable var vm: MediaViewModel
    let item: MediaItem
    let close: () -> Void
    @State private var sheet: DetailSheet?
    @State private var deleting = false
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.locale) private var locale

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("File details").font(.headline)
                Spacer()
                Button("Close", systemImage: "xmark", action: close).labelStyle(.iconOnly)
                    .accessibilityIdentifier("media.inspector.close")
            }.padding()
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    MediaThumbnail(item: item, large: true).frame(height: 210)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(item.displayName).font(.title3.weight(.semibold)).textSelection(.enabled)
                        Text(item.fileExtension.uppercased() + " · " + item.sizeText).foregroundStyle(.secondary)
                    }
                    if let url = URL(string: item.url ?? "") {
                        HStack {
                            Button("Open file", systemImage: "arrow.up.right.square") { openURL(url) }
                            Spacer()
                            ShareLink(item: url).labelStyle(.iconOnly)
                        }
                    }
                    Divider()
                    VStack(alignment: .leading, spacing: 12) {
                        property("File type", value: item.mimeType ?? "—")
                        if let width = item.width, let height = item.height { property("Dimensions", value: "\(width) × \(height) px") }
                        if item.uploadedMs > 0 {
                            property("Uploaded", value: Date(timeIntervalSince1970: Double(item.uploadedMs) / 1000).formatted(.dateTime.day().month().year().locale(locale)))
                        }
                    }.font(.callout).textSelection(.enabled)
                    Divider()
                    VStack(alignment: .leading, spacing: 14) {
                        metadata("Title", value: item.title)
                        metadata("Alternative text", value: item.alt)
                    }
                    if let error = vm.actionError { Text(error).foregroundStyle(.red).font(.callout) }
                    Button("Edit details…", systemImage: "pencil") { sheet = .edit }.disabled(!vm.canEdit)
                        .accessibilityIdentifier("media.edit")
                    if typeSize.isAccessibilitySize { VStack(alignment: .leading, spacing: 16) { fileActions } }
                    else { HStack { fileActions } }
                }.padding(20)
            }
        }
        .sheet(item: $sheet) { sheet in
            Group {
                switch sheet {
                case .edit: MediaDetailsEditor(vm: vm, item: item)
                case .move: MediaMoveSheet(vm: vm, ids: [item.id], onMoved: close)
                }
            }.dynamicTypeSize(typeSize)
        }
        .alert("Delete file?", isPresented: $deleting) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) { Task { if await vm.delete([item.id]) { close() } } }
        } message: { Text("This file will be permanently deleted, including where it is used in your shop.") }
    }

    @ViewBuilder private var fileActions: some View {
        Button("Move…", systemImage: "folder") { sheet = .move }.disabled(!vm.canEdit)
            .accessibilityIdentifier("media.inspector.move")
        if !typeSize.isAccessibilitySize { Spacer() }
        Button("Delete", systemImage: "trash", role: .destructive) { deleting = true }.disabled(!vm.canDelete)
            .accessibilityIdentifier("media.inspector.delete")
    }

    @ViewBuilder private func property(_ label: LocalizedStringKey, value: String) -> some View {
        if typeSize.isAccessibilitySize { metadata(label, value: value).frame(maxWidth: .infinity, alignment: .leading) }
        else { LabeledContent(label, value: value) }
    }

    private func metadata(_ label: LocalizedStringKey, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.callout.weight(.medium))
            Text(value.isEmpty ? String(localized: "Not set") : value).foregroundStyle(.secondary).textSelection(.enabled)
        }
    }
    private enum DetailSheet: String, Identifiable { case edit, move; var id: String { rawValue } }
}
