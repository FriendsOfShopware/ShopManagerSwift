import ShopwareAdminAPI

struct ProductMediaItem: Equatable, Identifiable, Sendable {
    let id: String
    let mediaID: String
    let name: String
    let url: String?
    let mimeType: String
    let position: Int
    init(_ entity: SwEntity, shopURL: String) {
        id = entity.id ?? ""
        let media = entity.entity("media")
        mediaID = entity.string("mediaId") ?? media?.id ?? ""
        name = media?.translated("title") ?? media?.string("fileName") ?? ""
        url = media?.string("url").map { rebaseMediaUrl($0, shopURL) }
        mimeType = media?.string("mimeType") ?? ""
        position = entity.int("position") ?? 0
    }
}
