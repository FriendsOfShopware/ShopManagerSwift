import SwiftUI

struct PromotionFormSheet<Content: View>: View {
    let title: LocalizedStringResource
    let busy: Bool
    let changed: Bool
    let canSave: Bool
    let error: String?
    var saveTitle: LocalizedStringResource = "Save"
    var idealHeight: CGFloat = 600
    let save: () async -> Bool
    @ViewBuilder let content: () -> Content
    var body: some View {
        EntityEditorSheet(title: title, identifier: "promotion", busy: busy, changed: changed, canSave: canSave, error: error,
                          saveTitle: saveTitle, idealHeight: idealHeight, save: save, content: content)
    }
}
