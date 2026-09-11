import Foundation

// Live media browsing — fetched on demand, not persisted.

struct MediaFolderItem: Equatable, Identifiable, Sendable {
    var id: String
    var name: String
    var childCount: Int
}

struct MediaItem: Equatable, Identifiable, Sendable {
    var id: String
    var fileName: String
    var fileExtension: String
    var mimeType: String?
    var fileSize: Int64
    var uploadedMs: Int64
    /// already rebased onto the shop's base URL
    var url: String?
    var isImage: Bool
    var title: String = ""
    var alt: String = ""
    var width: Int?
    var height: Int?
    var thumbnailURL: String?
    var folderId: String?

    var displayName: String { fileExtension.isEmpty ? fileName : "\(fileName).\(fileExtension)" }
    var sizeText: String { ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file) }
    var symbol: String {
        if isImage { return "photo" }
        if mimeType?.hasPrefix("video/") == true { return "film" }
        if mimeType?.hasPrefix("audio/") == true { return "waveform" }
        return fileExtension.lowercased() == "pdf" ? "doc.richtext" : "doc"
    }
}

enum MediaSort: String, CaseIterable, Identifiable {
    case newest, oldest, nameAscending, nameDescending, largest, smallest
    var id: String { rawValue }
    var title: String {
        switch self {
        case .newest: String(localized: "Newest first")
        case .oldest: String(localized: "Oldest first")
        case .nameAscending: String(localized: "Name, A–Z")
        case .nameDescending: String(localized: "Name, Z–A")
        case .largest: String(localized: "Largest first")
        case .smallest: String(localized: "Smallest first")
        }
    }
    var field: String {
        switch self {
        case .newest, .oldest: "uploadedAt"
        case .nameAscending, .nameDescending: "fileName"
        case .largest, .smallest: "fileSize"
        }
    }
    var ascending: Bool { self == .oldest || self == .nameAscending || self == .smallest }
}

enum MediaKind: String, CaseIterable, Identifiable {
    case all, images, videos, audio, documents
    var id: String { rawValue }
    var title: String {
        switch self {
        case .all: String(localized: "All files")
        case .images: String(localized: "Images")
        case .videos: String(localized: "Videos")
        case .audio: String(localized: "Audio")
        case .documents: String(localized: "Documents")
        }
    }
}
