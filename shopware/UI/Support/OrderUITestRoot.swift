#if DEBUG
import SwiftUI
import ShopwareAdminAPI

struct OrderUITestRoot: View {
    @State private var model: AppViewModel
    @State private var compactColumn = NavigationSplitViewColumn.detail
    private let shop = ConnectedShop(id: "order-fixture", name: "Storefront", baseUrl: "https://order-ui.test")
    private let arguments = ProcessInfo.processInfo.arguments
    init() {
        let transport = OrderUITestTransport(arguments: ProcessInfo.processInfo.arguments)
        let repo = AppRepository(directory: FileManager.default.temporaryDirectory.appendingPathComponent("order-ui-tests"), apiFactory: { shop in
            ShopApi(baseURL: shop.baseUrl, auth: .refreshToken(token: "fixture"), transport: transport)
        })
        _model = State(initialValue: AppViewModel(repo: repo))
    }
    var body: some View {
        NavigationSplitView(preferredCompactColumn: $compactColumn) {
            List { Label("Orders", systemImage: "doc.text").foregroundStyle(.tint) }
                .navigationTitle("Storefront").navigationSplitViewColumnWidth(200)
        } detail: {
            NavigationStack {
                if arguments.contains("--order-detail") { OrderDetailView(shop: shop, orderId: "order-0") }
                else { OrdersView(shop: shop) }
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
