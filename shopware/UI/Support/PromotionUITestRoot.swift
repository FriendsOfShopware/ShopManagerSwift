#if DEBUG
import SwiftUI
import ShopwareAdminAPI

struct PromotionUITestRoot: View {
    @State private var model: AppViewModel
    @State private var compactColumn = NavigationSplitViewColumn.detail
    private let shop = ConnectedShop(id: "promotion-fixture", name: "Storefront", baseUrl: "https://promotion-ui.test")
    private let arguments = ProcessInfo.processInfo.arguments
    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let transport = PromotionUITestTransport(arguments: arguments, count: arguments.contains("--many-promotions") ? 31 : 3)
        let repo = AppRepository(directory: FileManager.default.temporaryDirectory.appendingPathComponent("promotion-ui-tests"), apiFactory: { shop in
            ShopApi(baseURL: shop.baseUrl, auth: .refreshToken(token: "fixture"), transport: transport)
        })
        _model = State(initialValue: AppViewModel(repo: repo))
    }
    var body: some View {
        NavigationSplitView(columnVisibility: .constant(arguments.contains("--wide-table") ? .detailOnly : .automatic), preferredCompactColumn: $compactColumn) {
            List { Label("Promotions", systemImage: "tag").foregroundStyle(.tint) }
                .navigationTitle("Storefront").navigationSplitViewColumnWidth(200)
        } detail: {
            NavigationStack {
                if arguments.contains("--promotion-detail") { PromotionDetailView(shop: shop, promotionID: "promotion-0") }
                else { PromosView(shop: shop) }
            }
        }
        .environment(model)
        .dynamicTypeSize(arguments.contains("--large-text") ? .accessibility3 : .large)
        #if os(macOS)
        .background(AppUITestWindowPlacement(size: CGSize(width: 1024, height: 677)))
        #endif
    }
}
#endif
