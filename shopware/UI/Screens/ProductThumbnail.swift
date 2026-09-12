import SwiftUI

struct ProductThumbnail: View {
    let url: String?
    var size: CGFloat = 48
    var body: some View {
        AsyncImage(url: url.flatMap(URL.init(string:))) { phase in
            if let image = phase.image { image.resizable().scaledToFit() }
            else { Image(systemName: "shippingbox").font(.title2).foregroundStyle(.secondary) }
        }
        .frame(width: size, height: size).background(.quaternary.opacity(0.35), in: .rect(cornerRadius: 8))
        .clipShape(.rect(cornerRadius: 8)).accessibilityHidden(true)
    }
}
