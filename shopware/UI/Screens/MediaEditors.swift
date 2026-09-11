import SwiftUI

struct MediaFolderEditor: View {
    @Bindable var vm: MediaViewModel
    let folder: MediaFolderItem?
    @State private var name: String
    @State private var confirmDiscard = false
    @Environment(\.dismiss) private var dismiss

    init(vm: MediaViewModel, folder: MediaFolderItem?) {
        self.vm = vm; self.folder = folder
        _name = State(initialValue: folder?.name ?? "")
    }
    var body: some View {
        NavigationStack {
            Form {
                Section("Folder name") {
                    TextField("Folder name", text: $name).labelsHidden().accessibilityIdentifier("media.folderName")
                }
                if let error = vm.actionError { Text(error).foregroundStyle(.red) }
            }.groupedFormStyle().disabled(vm.busy)
                .navigationTitle(folder == nil ? "New folder" : "Rename folder")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if dirty { confirmDiscard = true } else { dismiss() } }.disabled(vm.busy) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") { Task { if await vm.saveFolder(name: name, folder: folder) { dismiss() } } }
                            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || vm.busy)
                            .accessibilityIdentifier("media.folder.save")
                    }
                }
        }
        .onAppear { vm.actionError = nil }.interactiveDismissDisabled(vm.busy || dirty)
        .alert("Discard changes?", isPresented: $confirmDiscard) {
            Button("Keep editing", role: .cancel) { }
            Button("Discard changes", role: .destructive) { dismiss() }
        }
        #if os(macOS)
        .frame(width: 420, height: 220)
        #else
        .presentationDetents([.medium])
        #endif
    }
    private var dirty: Bool { name != (folder?.name ?? "") }
}

struct MediaDetailsEditor: View {
    @Bindable var vm: MediaViewModel
    let item: MediaItem
    @State private var fileName: String
    @State private var title: String
    @State private var alt: String
    @State private var confirmDiscard = false
    @Environment(\.dismiss) private var dismiss

    init(vm: MediaViewModel, item: MediaItem) {
        self.vm = vm; self.item = item
        _fileName = State(initialValue: item.fileName)
        _title = State(initialValue: item.title)
        _alt = State(initialValue: item.alt)
    }
    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("File name", text: $fileName).labelsHidden().accessibilityIdentifier("media.fileName")
                } header: { Text("File name")
                } footer: { Text("The file extension stays .\(item.fileExtension). Renaming changes the file's URL.") }
                Section("Title") {
                    TextField("Title", text: $title).labelsHidden().accessibilityIdentifier("media.title")
                }
                Section {
                    TextField("Alternative text", text: $alt, axis: .vertical).labelsHidden().lineLimit(2...4)
                        .accessibilityIdentifier("media.alt")
                } header: { Text("Alternative text")
                } footer: { Text("Describe the image for people who can't see it. This text can be used by screen readers in your storefront.") }
                if let error = vm.actionError { Section { Text(error).foregroundStyle(.red) } }
            }.groupedFormStyle().disabled(vm.busy)
                .navigationTitle("Edit file details")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { if dirty { confirmDiscard = true } else { dismiss() } }.disabled(vm.busy) }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            Task { if await vm.saveDetails(item: item, fileName: fileName.trimmingCharacters(in: .whitespacesAndNewlines), title: title, alt: alt) { dismiss() } }
                        }.disabled(!validName || !dirty || vm.busy).accessibilityIdentifier("media.details.save")
                    }
                }
        }.onAppear { vm.actionError = nil }.interactiveDismissDisabled(vm.busy || dirty)
        .alert("Discard changes?", isPresented: $confirmDiscard) {
            Button("Keep editing", role: .cancel) { }
            Button("Discard changes", role: .destructive) { dismiss() }
        }
        #if os(macOS)
        .frame(width: 500, height: 480)
        #endif
    }
    private var dirty: Bool { fileName != item.fileName || title != item.title || alt != item.alt }
    private var validName: Bool {
        let name = fileName.trimmingCharacters(in: .whitespacesAndNewlines)
        return !name.isEmpty && !name.contains("/") && !name.contains("\\")
    }
}
