#if DEBUG
import SwiftUI
import ShopwareAdminAPI

/// Launch-only fixtures exercise production views with no network or persisted shop credentials.
struct CustomerUITestRoot: View {
    @State private var model: AppViewModel
    private let shop = ConnectedShop(id: "ui-shop", name: "Customer UI fixtures", baseUrl: "https://customer-ui.test")
    private let arguments = ProcessInfo.processInfo.arguments

    init() {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("customer-ui-tests")
        let transport = CustomerUITestTransport(arguments: ProcessInfo.processInfo.arguments)
        let repo = AppRepository(directory: directory, apiFactory: { shop in
            ShopApi(baseURL: shop.baseUrl, auth: .refreshToken(token: "fixture"), transport: transport)
        })
        _model = State(initialValue: AppViewModel(repo: repo))
    }

    var body: some View {
        NavigationStack { CustomersView(shop: shop) }
            .environment(model)
            .dynamicTypeSize(arguments.contains("--large-text") ? .accessibility3 : .large)
            .frame(maxWidth: arguments.contains("--narrow-window") ? 420 : .infinity)
            #if os(macOS)
            .background(AppUITestWindowPlacement())
            #endif
    }
}

#if os(macOS)
/// Keep automation on the primary display, independent of saved windows and attached monitors.
struct AppUITestWindowPlacement: NSViewRepresentable {
    var size = CGSize(width: 1100, height: 760)
    func makeNSView(context: Context) -> PlacementView {
        let view = PlacementView()
        view.preferredSize = size
        return view
    }
    func updateNSView(_ nsView: PlacementView, context: Context) {}

    final class PlacementView: NSView {
        var preferredSize = CGSize.zero
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, let screen = NSScreen.screens.first else { return }
            let visible = screen.visibleFrame
            let size = NSSize(width: min(preferredSize.width, visible.width), height: min(preferredSize.height, visible.height))
            window.setFrame(NSRect(x: visible.midX - size.width / 2,
                                   y: visible.midY - size.height / 2,
                                   width: size.width, height: size.height), display: true)
        }
    }
}
#endif

#endif
