#if DEBUG
import SwiftUI
import ShopwareAdminAPI

struct ProductUITestRoot: View {
    @State private var model: AppViewModel
    @State private var compactColumn = NavigationSplitViewColumn.detail
    @State private var quickEditing = false
    private let shop = ConnectedShop(id: "product-fixture", name: "Storefront", baseUrl: "https://product-ui.test", currency: "USD")
    private let arguments = ProcessInfo.processInfo.arguments
    init() {
        let arguments = ProcessInfo.processInfo.arguments
        let transport = ProductUITestTransport(arguments: arguments, images: MediaUITestRoot.artwork(), count: arguments.contains("--many-products") ? 31 : 3,
                                               variants: arguments.contains("--many-variants") ? 132 : 32)
        let repo = AppRepository(directory: FileManager.default.temporaryDirectory.appendingPathComponent("product-ui-tests"), apiFactory: { shop in
            ShopApi(baseURL: shop.baseUrl, auth: .refreshToken(token: "fixture"), transport: transport)
        })
        _model = State(initialValue: AppViewModel(repo: repo))
    }
    var body: some View {
        NavigationSplitView(columnVisibility: .constant(arguments.contains("--wide-table") ? .detailOnly : .automatic), preferredCompactColumn: $compactColumn) {
            List { Label("Products", systemImage: "shippingbox").foregroundStyle(.tint) }
                .navigationTitle("Storefront").navigationSplitViewColumnWidth(200)
        } detail: {
            NavigationStack {
                if arguments.contains("--product-detail") { ProductDetailView(shop: shop, productId: "product-0") }
                else { ProductsView(shop: shop) }
            }
        }
        .environment(model)
        .sheet(isPresented: $quickEditing) { ProductActionSheet(shop: shop, productId: "product-0").environment(model) }
        .task { quickEditing = arguments.contains("--product-quick") }
        .dynamicTypeSize(arguments.contains("--large-text") ? .accessibility3 : .large)
        #if os(macOS)
        .background(AppUITestWindowPlacement(size: CGSize(width: 1100, height: 740)))
        #endif
    }
}
#endif
