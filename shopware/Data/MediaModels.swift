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
}
