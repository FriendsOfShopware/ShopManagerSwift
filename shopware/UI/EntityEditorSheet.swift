import SwiftUI

/// Native form presentation shared by module editors, with a retained draft on
/// failure and explicit discard behavior on every platform.
struct EntityEditorSheet<Content: View>: View {
    let title: LocalizedStringResource
    let identifier: String
    let busy: Bool
    let changed: Bool
    let canSave: Bool
    let error: String?
    var saveTitle: LocalizedStringResource = "Save"
    var idealHeight: CGFloat = 600
    let save: () async -> Bool
    @ViewBuilder let content: () -> Content
    @Environment(\.dismiss) private var dismiss
    @State private var discarding = false
    var body: some View {
        NavigationStack {
            Form { content() }.groupedFormStyle().accessibilityIdentifier(identifier + ".editor.form").disabled(busy)
                .scrollDismissesKeyboard(.immediately)
                .safeAreaInset(edge: .top, spacing: 0) {
                    if let error {
                        Label(error, systemImage: "exclamationmark.triangle").labelStyle(.titleAndIcon)
                            .foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
                            .fixedSize(horizontal: false, vertical: true).padding().background(.background)
                            .accessibilityIdentifier(identifier + ".saveError")
                    }
                }
                .navigationTitle(Text(title))
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { if changed { discarding = true } else { dismiss() } }.disabled(busy)
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button { Task { if await save() { dismiss() } } } label: { Text(saveTitle) }
                            .disabled(!canSave || busy).keyboardShortcut("s", modifiers: .command)
                            .accessibilityIdentifier(identifier + ".editor.save")
                    }
                }
                .confirmationDialog("Discard changes?", isPresented: $discarding, titleVisibility: .visible) {
                    Button("Discard changes", role: .destructive) { dismiss() }
                }
        }
        .interactiveDismissDisabled(changed || busy)
        #if os(macOS)
        .frame(minWidth: 460, idealWidth: 580, minHeight: 320, idealHeight: idealHeight).presentationSizing(.fitted)
        #endif
    }
}
