import Foundation
import ShopwareAdminAPI

/// Folders are few — loaded un-paged per level.
func mediaFolderCriteria(_ parentId: String?) -> Criteria {
    Criteria()
        .setLimit(100)
        .addFilter(Criteria.equals("parentId", parentId.map(JSONValue.string)))
        .addSorting("name")
        .addIncludes("media_folder", ["id", "name", "childCount"])
}

func mediaListCriteria(_ folderId: String?) -> Criteria {
    Criteria()
        .addFilter(Criteria.equals("mediaFolderId", folderId.map(JSONValue.string)))
        .addSorting("uploadedAt", "DESC")
        .addIncludes(
            "media",
            ["id", "fileName", "fileExtension", "mimeType", "fileSize", "uploadedAt", "url"]
        )
}

func parseMediaFolder(_ f: SwEntity) -> MediaFolderItem {
    MediaFolderItem(
        id: f.id ?? "",
        name: f.string("name") ?? "—",
        childCount: f.int("childCount") ?? 0
    )
}

func parseMedia(_ m: SwEntity, _ shopBaseUrl: String) -> MediaItem {
    MediaItem(
        id: m.id ?? "",
        fileName: m.string("fileName") ?? "—",
        fileExtension: m.string("fileExtension") ?? "",
        mimeType: m.string("mimeType"),
        fileSize: m.long("fileSize") ?? 0,
        uploadedMs: m.date("uploadedAt")?.epochMs ?? 0,
        url: m.string("url").map { rebaseMediaUrl($0, shopBaseUrl) },
        isImage: (m.string("mimeType")?.hasPrefix("image/")) ?? false
    )
}
