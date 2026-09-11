import SwiftUI

struct CustomerInfoCard<Content: View>: View {
    let title: LocalizedStringKey
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title).font(.headline)
            VStack(alignment: .leading, spacing: 12, content: content)
                .textSelection(.enabled)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
