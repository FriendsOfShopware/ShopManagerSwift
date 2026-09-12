#if DEBUG
import SwiftUI
import ShopwareAdminAPI

struct ReviewUITestRoot: View {
    @State private var model: AppViewModel
    @State private var compactColumn = NavigationSplitViewColumn.detail
    private let shop = ConnectedShop(id: "review-fixture", name: "Storefront", baseUrl: "https://review-ui.test")
    private let arguments = ProcessInfo.processInfo.arguments
    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let transport = ReviewUITestTransport(arguments: arguments, count: arguments.contains("--many-reviews") ? 31 : 3)
        let repo = AppRepository(directory: FileManager.default.temporaryDirectory.appendingPathComponent("review-ui-tests"), apiFactory: { shop in
            ShopApi(baseURL: shop.baseUrl, auth: .refreshToken(token: "fixture"), transport: transport)
        })
        _model = State(initialValue: AppViewModel(repo: repo))
    }
    var body: some View {
        NavigationSplitView(preferredCompactColumn: $compactColumn) {
            List { Label("Reviews", systemImage: "star.bubble").foregroundStyle(.tint) }
                .navigationTitle("Storefront").navigationSplitViewColumnWidth(200)
        } detail: {
            NavigationStack {
                if arguments.contains("--review-detail") { ReviewDetailView(shop: shop, reviewID: "review-0") }
                else { ReviewInboxView(shop: shop) }
            }
        }
        .environment(model)
        .dynamicTypeSize(arguments.contains("--large-text") ? .accessibility3 : .large)
        #if os(macOS)
        .background(AppUITestWindowPlacement())
        #endif
    }
}
#endif
