import SwiftUI

struct MediaThumbnail: View {
    let item: MediaItem
    var large = false
    var body: some View {
        ZStack {
            Rectangle().fill(.quaternary.opacity(0.45))
            if item.isImage, let url = URL(string: (large ? item.url : item.thumbnailURL ?? item.url) ?? "") {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFit().padding(large ? 8 : 4)
                    case .failure: placeholder(symbol: "photo.badge.exclamationmark")
                    case .empty: ProgressView().controlSize(.small)
                    @unknown default: placeholder(symbol: item.symbol)
                    }
                }
            } else { placeholder(symbol: item.symbol) }
        }.clipShape(.rect(cornerRadius: large ? 12 : 8)).accessibilityHidden(true)
    }
    private func placeholder(symbol: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: symbol).font(.system(size: large ? 52 : 28)).foregroundStyle(.secondary)
            if large { Text(item.fileExtension.uppercased()).font(.caption.weight(.medium)).foregroundStyle(.secondary) }
        }
    }
}

struct MediaFolderLabel: View {
    let folder: MediaFolderItem
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 3) {
                Text(folder.name).foregroundStyle(.primary).lineLimit(typeSize.isAccessibilitySize ? nil : 1)
                Text("\(folder.childCount) subfolders").font(.caption).foregroundStyle(.secondary)
            }
        } icon: { Image(systemName: "folder.fill").font(.title2).foregroundStyle(.tint) }
    }
}

struct MediaFileRow: View {
    let item: MediaItem
    var body: some View {
        HStack(spacing: 12) {
            MediaThumbnail(item: item).frame(width: 44, height: 44)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.displayName).foregroundStyle(.primary).lineLimit(2)
                Text(item.fileExtension.uppercased() + " · " + item.sizeText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }.padding(.vertical, 3).contentShape(.rect)
    }
}
