import Foundation
import ShopwareAdminAPI

func mediaFolderCriteria(_ parentId: String?, page: Int = 1, term: String = "") -> Criteria {
    let criteria = Criteria()
        .setLimit(100)
        .setPage(page)
        .setTotalCountMode(.exact)
        .addFilter(Criteria.equals("parentId", parentId.map(JSONValue.string)))
        .addSorting("name")
        .addSorting("id")
        .addIncludes("media_folder", ["id", "name", "childCount"])
    if !term.isEmpty { criteria.addFilter(Criteria.contains("name", term)) }
    return criteria
}

func mediaListCriteria(_ folderId: String?, sort: MediaSort = .newest, kind: MediaKind = .all) -> Criteria {
    let criteria = Criteria()
        .addFilter(Criteria.equals("mediaFolderId", folderId.map(JSONValue.string)))
        .addSorting(sort.field, sort.ascending ? "ASC" : "DESC")
        .addSorting("id", "ASC")
        .addAssociation("thumbnails")
        .addIncludes(
            "media",
            ["id", "fileName", "fileExtension", "mimeType", "fileSize", "uploadedAt", "url", "mediaFolderId", "title", "alt", "translated", "metaData", "thumbnails"]
        )
        .addIncludes("media_thumbnail", ["id", "url", "width", "height"])
    switch kind {
    case .all: break
    case .images: criteria.addFilter(Criteria.contains("mimeType", "image/"))
    case .videos: criteria.addFilter(Criteria.contains("mimeType", "video/"))
    case .audio: criteria.addFilter(Criteria.contains("mimeType", "audio/"))
    case .documents: criteria.addFilter(Criteria.multi("OR", Criteria.contains("mimeType", "application/"), Criteria.contains("mimeType", "text/")))
    }
    return criteria
}

func parseMediaFolder(_ f: SwEntity) -> MediaFolderItem {
    MediaFolderItem(
        id: f.id ?? "",
        name: f.string("name") ?? "—",
        childCount: f.int("childCount") ?? 0
    )
}

func parseMedia(_ m: SwEntity, _ shopBaseUrl: String) -> MediaItem {
    let thumbnails = m.entities("thumbnails").sorted { ($0.int("width") ?? 0) < ($1.int("width") ?? 0) }
    let thumbnail = thumbnails.first { ($0.int("width") ?? 0) >= 320 } ?? thumbnails.last
    return MediaItem(
        id: m.id ?? "",
        fileName: m.string("fileName") ?? "—",
        fileExtension: m.string("fileExtension") ?? "",
        mimeType: m.string("mimeType"),
        fileSize: m.long("fileSize") ?? 0,
        uploadedMs: m.date("uploadedAt")?.epochMs ?? 0,
        url: m.string("url").map { rebaseMediaUrl($0, shopBaseUrl) },
        isImage: (m.string("mimeType")?.hasPrefix("image/")) ?? false,
        title: m.translated("title") ?? "", alt: m.translated("alt") ?? "",
        width: m.json["metaData"]?["width"]?.intValue,
        height: m.json["metaData"]?["height"]?.intValue,
        thumbnailURL: thumbnail?.string("url").map { rebaseMediaUrl($0, shopBaseUrl) },
        folderId: m.string("mediaFolderId")
    )
}
