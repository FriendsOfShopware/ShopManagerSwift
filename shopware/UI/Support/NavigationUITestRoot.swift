#if DEBUG
import SwiftUI
import ShopwareAdminAPI

/// Exercises MainView itself; module-only fixtures intentionally bypass the app's navigation.
struct NavigationUITestRoot: View {
    @State private var model: AppViewModel
    @State private var ready = false
    @State private var compact = false
    private let directory: URL
    private let arguments = ProcessInfo.processInfo.arguments

    init() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("navigation-ui-" + UUID().uuidString)
        self.directory = directory
        let transport = NavigationUITestTransport()
        _model = State(initialValue: AppViewModel(repo: AppRepository(directory: directory, apiFactory: { shop in
            ShopApi(baseURL: shop.baseUrl, auth: .refreshToken(token: "fixture"), transport: transport)
        })))
    }

    var body: some View {
        Group {
            if ready {
                #if os(iOS)
                GeometryReader { geometry in
                    MainView(onAddShop: {})
                        .frame(width: compact ? min(540, geometry.size.width) : geometry.size.width)
                        .environment(\.horizontalSizeClass, compact ? .compact : geometry.size.width > 600 ? .regular : .compact)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .overlay(alignment: .bottomTrailing) {
                    if arguments.contains("--resize-navigation") {
                        Button { compact.toggle() } label: { Text(verbatim: "Resize fixture") }
                            .accessibilityIdentifier("navigation.fixture.resize")
                    }
                }
                #else
                MainView(onAddShop: {}).background(AppUITestWindowPlacement())
                #endif
            } else {
                ProgressView()
            }
        }
        .environment(model)
        .dynamicTypeSize(arguments.contains("--large-text") ? .accessibility3 : .large)
        .task {
            guard !ready else { return }
            var data = AppData()
            data.shops = [
                ConnectedShop(id: "storefront", name: "Storefront", baseUrl: "https://navigation-ui.test"),
                ConnectedShop(id: "limited", name: "Customer service", baseUrl: "https://navigation-ui.test",
                              scopes: ["order": false, "product": false, "promotion": false, "media": false, "product_review": false]),
                ConnectedShop(id: "outlet", name: "Outlet", baseUrl: "https://navigation-ui.test")
            ]
            data.selectedShopId = "storefront"
            data.onboardingSeen = true
            await AppStore(directory: directory).save(data)
            let snapshots = SnapshotStore(dir: directory.appendingPathComponent("snapshots"))
            for shop in data.shops {
                var snapshot = ShopSnapshot()
                snapshot.todayRevenue = 1249.90
                snapshot.ordersToday = 12
                snapshot.openOrders = 4
                snapshot.weekRevenue = [220, 340, 290, 410, 600, 710, 1249.90]
                snapshot.lastSyncEpochMs = Date().epochMs
                snapshots.write(shop.id, snapshot)
            }
            await model.bootstrap()
            ready = true
            if arguments.contains("--navigation-deep-link") {
                model.handleNotification(shopId: "outlet", orderId: "order-0")
            }
        }
    }
}
#endif
