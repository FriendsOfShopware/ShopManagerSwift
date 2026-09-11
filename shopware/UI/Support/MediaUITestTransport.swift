#if DEBUG
import Foundation
import ShopwareAdminAPI

actor MediaUITestTransport: HTTPTransport {
    private var failures: Set<String>
    private let readOnly: Bool
    private var media: [JSONValue]
    private var folders: [JSONValue]
    private(set) var requests: [HTTPRequest] = []
    private(set) var slowSearchStarted = false

    init(arguments: [String] = [], images: [String: String] = [:], extraFiles: Int = 0, extraFolders: Int = 0) {
        failures = Set(arguments); readOnly = arguments.contains("--read-only")
        folders = [
            .object(["id": "products", "name": "Products", "parentId": .null, "childCount": 1]),
            .object(["id": "campaigns", "name": "Campaigns", "parentId": .null, "childCount": 0]),
            .object(["id": "summer", "name": "Summer collection", "parentId": "products", "childCount": 0]),
        ] + (0..<extraFolders).map { .object(["id": .string("folder-\($0)"), "name": .string("Folder \($0)"), "parentId": .null, "childCount": 0]) }
        let seeds = [("image-1", "linen-shirt-sand", "png", "image/png"), ("image-2", "everyday-tote", "png", "image/png"),
                     ("image-3", "ceramic-coffee-cup", "png", "image/png"), ("document", "spring-catalogue", "pdf", "application/pdf"),
                     ("video", "brand-story", "mp4", "video/mp4"), ("audio", "store-introduction", "mp3", "audio/mpeg")]
        media = seeds.enumerated().map { index, seed in
            .object(["id": .string(seed.0), "fileName": .string(seed.1), "fileExtension": .string(seed.2), "mimeType": .string(seed.3),
                     "fileSize": .int(120_000 + index * 450_000), "uploadedAt": .string(String(format: "2026-09-%02dT10:00:00.000+00:00", 10 - index)),
                     "mediaFolderId": .null, "title": .string(index == 0 ? "Linen shirt in sand" : ""), "alt": "",
                     "url": images[seed.0].map(JSONValue.string) ?? .null,
                     "metaData": index < 3 ? .object(["width": 1600, "height": 1200]) : .null])
        } + (0..<extraFiles).map { .object(["id": .string("extra-\($0)"), "fileName": .string("Extra \($0)"), "mediaFolderId": .null]) }
        if arguments.contains("--empty-media") { media = []; folders = [] }
    }

    func perform(_ request: HTTPRequest) async throws -> HTTPResponse {
        guard let url = URL(string: request.url), url.host == "media-ui.test" else {
            throw ApiError.network(message: "Media fixtures reject non-fixture hosts.", underlying: nil)
        }
        let path = url.path
        let payload = request.body.flatMap(JSONValue.parse)
        if path.hasSuffix("/oauth/token") { return response(.object(["access_token": "fixture", "expires_in": 3600])) }
        requests.append(request)
        if path.hasSuffix("/_info/me") {
            try failOnce("--fail-permissions-once")
            return response(.object(["data": .object(["id": "fixture", "admin": .bool(!readOnly), "aclRoles": .array([])])]))
        }
        if path.contains("/search/") {
            let isMedia = path.hasSuffix("/media")
            if isMedia { try failOnce("--fail-list-once") }
            if isMedia && payload?["page"]?.intValue == 2 { try failOnce("--fail-page-once") }
            if payload?["term"]?.stringValue == "slow" {
                slowSearchStarted = true
                try await Task.sleep(for: .milliseconds(300))
            }
            var rows = isMedia ? media : folders
            for filter in payload?["filter"]?.arrayValue ?? [] { rows = rows.filter { matches($0, filter) } }
            if let term = payload?["term"]?.stringValue, !term.isEmpty {
                rows = rows.filter { ($0["fileName"]?.stringValue ?? "").localizedCaseInsensitiveContains(term) }
            }
            let sort = payload?["sort"]?.arrayValue ?? []
            rows.sort { left, right in
                for criterion in sort {
                    let key = criterion["field"]?.stringValue ?? "id"
                    let a = left[key]?.stringValue ?? String(left[key]?.intValue ?? 0)
                    let b = right[key]?.stringValue ?? String(right[key]?.intValue ?? 0)
                    let order = a.compare(b, options: [.numeric, .caseInsensitive])
                    if order != .orderedSame { return criterion["order"]?.stringValue == "DESC" ? order == .orderedDescending : order == .orderedAscending }
                }
                return false
            }
            let total = rows.count, page = payload?["page"]?.intValue ?? 1, limit = payload?["limit"]?.intValue ?? 100
            return response(.object(["total": .int(total), "data": .array(Array(rows.dropFirst((page - 1) * limit).prefix(limit)))]))
        }
        guard !readOnly else { throw ApiError.server(status: 403, message: "Read-only fixture") }
        if path.hasSuffix("/rename"), let id = path.split(separator: "/").dropLast().last {
            try failOnce("--fail-save-once")
            update(&media, id: String(id), payload: .object(["fileName": payload?["fileName"] ?? .null]))
        } else if path.contains("/_action/media/"), path.hasSuffix("/upload") {
            return HTTPResponse(status: 204, body: Data())
        } else if request.method == .patch {
            try failOnce("--fail-save-once")
            if path.contains("/media-folder/") { update(&folders, id: url.lastPathComponent, payload: payload ?? .null) }
            else { update(&media, id: url.lastPathComponent, payload: payload ?? .null) }
        } else if request.method == .delete {
            if url.lastPathComponent == "image-2" { try failOnce("--fail-delete-once") }
            media.removeAll { $0["id"]?.stringValue == url.lastPathComponent }
        } else if request.method == .post, let payload {
            if path.hasSuffix("/media-folder") { folders.append(payload) }
            else if path.hasSuffix("/media") { media.append(payload) }
            else { throw ApiError.server(status: 500, message: "Unexpected fixture route: \(path)") }
        } else { throw ApiError.server(status: 500, message: "Unexpected fixture route: \(path)") }
        return HTTPResponse(status: 204, body: Data())
    }

    private func update(_ rows: inout [JSONValue], id: String, payload: JSONValue) {
        guard let index = rows.firstIndex(where: { $0["id"]?.stringValue == id }), var row = rows[index].objectValue else { return }
        row.merge(payload.objectValue ?? [:], uniquingKeysWith: { _, new in new }); rows[index] = .object(row)
    }
    private func matches(_ row: JSONValue, _ filter: JSONValue) -> Bool {
        let field = filter["field"]?.stringValue ?? ""
        switch filter["type"]?.stringValue {
        case "equals": return (row[field] ?? .null) == (filter["value"] ?? .null)
        case "contains": return (row[field]?.stringValue ?? "").localizedCaseInsensitiveContains(filter["value"]?.stringValue ?? "")
        case "multi":
            let matches = (filter["queries"]?.arrayValue ?? []).map { self.matches(row, $0) }
            return filter["operator"]?.stringValue == "OR" ? matches.contains(true) : !matches.contains(false)
        default: return false
        }
    }
    private func failOnce(_ flag: String) throws {
        if failures.remove(flag) != nil { throw ApiError.server(status: 500, message: "Fixture request failed. Please retry.") }
    }
    private func response(_ value: JSONValue) -> HTTPResponse { HTTPResponse(status: 200, body: value.encoded()) }
}
#endif
