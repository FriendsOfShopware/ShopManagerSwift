import SwiftUI

struct PromotionNotice: View {
    let message: String
    let retry: () -> Void
    var body: some View {
        HStack(alignment: .top) {
            Label(message, systemImage: "exclamationmark.triangle").labelStyle(.titleAndIcon).foregroundStyle(.red)
            Spacer()
            Button("Retry", action: retry)
        }.padding().fixedSize(horizontal: false, vertical: true)
    }
}
