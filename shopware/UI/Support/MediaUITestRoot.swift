#if DEBUG
import SwiftUI
import ShopwareAdminAPI

struct MediaUITestRoot: View {
    @State private var model: AppViewModel
    @State private var compactColumn = NavigationSplitViewColumn.detail
    private let shop = ConnectedShop(id: "media-fixture", name: "Storefront", baseUrl: "https://media-ui.test")
    private let arguments = ProcessInfo.processInfo.arguments
    private static let preferences: UserDefaults = {
        let defaults = UserDefaults(suiteName: "media-ui-fixtures")!
        defaults.set("grid", forKey: "media.presentation")
        return defaults
    }()

    init() {
        let transport = MediaUITestTransport(arguments: ProcessInfo.processInfo.arguments, images: Self.artwork())
        let repo = AppRepository(directory: FileManager.default.temporaryDirectory.appendingPathComponent("media-ui-tests"), apiFactory: { shop in
            ShopApi(baseURL: shop.baseUrl, auth: .refreshToken(token: "fixture"), transport: transport)
        })
        _model = State(initialValue: AppViewModel(repo: repo))
    }

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $compactColumn) {
            List { Label("Media", systemImage: "photo.on.rectangle").foregroundStyle(.tint) }
                .navigationTitle("Storefront").navigationSplitViewColumnWidth(200)
        } detail: { NavigationStack { MediaView(shop: shop) } }
            .environment(model)
            .defaultAppStorage(Self.preferences)
            .dynamicTypeSize(arguments.contains("--large-text") ? .accessibility3 : .large)
            #if os(macOS)
            .background(AppUITestWindowPlacement())
            #endif
    }

    /// Deterministic, offline preview images exercise the same AsyncImage path as shop media.
    private static func artwork() -> [String: String] {
        var result: [String: String] = [:]
        for (id, symbol, color) in [("image-1", "tshirt.fill", Color.brown), ("image-2", "bag.fill", Color.teal), ("image-3", "cup.and.saucer.fill", Color.orange)] {
            let renderer = ImageRenderer(content: ZStack {
                color.opacity(0.12)
                Image(systemName: symbol).font(.system(size: 120)).foregroundStyle(color)
            }.frame(width: 400, height: 300))
            #if os(macOS)
            let data = renderer.nsImage?.tiffRepresentation.flatMap { NSBitmapImageRep(data: $0)?.representation(using: .png, properties: [:]) }
            #else
            let data = renderer.uiImage?.pngData()
            #endif
            if let data { result[id] = "data:image/png;base64," + data.base64EncodedString() }
        }
        return result
    }
}
#endif
