import SwiftUI

struct MediaMoveSheet: View {
    @Bindable var vm: MediaViewModel
    let ids: Set<String>
    var onMoved: () -> Void = { }
    @Environment(\.dismiss) private var dismiss
    @State private var path: [MediaFolderItem] = []
    @State private var folders: [MediaFolderItem] = []
    @State private var loading = false
    @State private var error: String?
    @State private var remaining: Set<String>?
    private var destination: String? { path.last?.id }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Choose a destination for \(ids.count) files.").foregroundStyle(.secondary)
                    Label(path.last?.name ?? String(localized: "Media library"), systemImage: "folder")
                        .font(.headline).accessibilityIdentifier("media.move.destination")
                }.frame(maxWidth: .infinity, alignment: .leading).padding()
                Divider()
                if loading { ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity) }
                else if let error {
                    ContentUnavailableView { Label("Couldn't load folders", systemImage: "exclamationmark.triangle") }
                    description: { Text(error) } actions: { Button("Retry") { Task { await load() } } }
                } else {
                    List {
                        if !path.isEmpty {
                            Button("Parent folder", systemImage: "arrow.up") { path.removeLast() }
                                .accessibilityIdentifier("media.move.parent")
                        }
                        ForEach(folders) { folder in
                            Button { if path.last?.id != folder.id { path.append(folder) } } label: {
                                HStack { MediaFolderLabel(folder: folder); Spacer(); Image(systemName: "chevron.right").foregroundStyle(.tertiary) }
                                    .contentShape(.rect)
                            }.buttonStyle(.plain).accessibilityIdentifier("media.move.folder.\(folder.id)")
                        }
                        if folders.isEmpty { Text("No subfolders").foregroundStyle(.secondary) }
                    }
                }
                if let error = vm.actionError { Text(error).foregroundStyle(.red).font(.callout).padding() }
            }
            .disabled(vm.busy).navigationTitle("Move files")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() }.disabled(vm.busy) }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Move here") {
                        Task {
                            if await vm.move(remaining ?? ids, to: destination) { dismiss(); onMoved() }
                            else { remaining = vm.selection }
                        }
                    }.disabled(loading || error != nil || !vm.canEdit || destination == vm.folderId)
                        .accessibilityIdentifier("media.move.confirm")
                }
            }
        }
        .task(id: destination) { await load() }
        .onAppear { vm.actionError = nil }.interactiveDismissDisabled(vm.busy)
        #if os(macOS)
        .frame(width: 440, height: 420)
        #endif
    }
    private func load() async {
        loading = true; error = nil
        defer { loading = false }
        do { let result = try await vm.fetchFolders(parentId: destination); try Task.checkCancellation(); folders = result }
        catch is CancellationError { }
        catch { self.error = error.localizedDescription }
    }
}
