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
            .background(CustomerUITestWindowPlacement())
            #endif
    }
}

#if os(macOS)
/// Keep automation on the primary display, independent of saved windows and attached monitors.
private struct CustomerUITestWindowPlacement: NSViewRepresentable {
    func makeNSView(context: Context) -> PlacementView { PlacementView() }
    func updateNSView(_ nsView: PlacementView, context: Context) {}

    final class PlacementView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, let screen = NSScreen.screens.first else { return }
            let visible = screen.visibleFrame
            let size = NSSize(width: min(1100, visible.width), height: min(760, visible.height))
            window.setFrame(NSRect(x: visible.midX - size.width / 2,
                                   y: visible.midY - size.height / 2,
                                   width: size.width, height: size.height), display: true)
        }
    }
}
#endif

#endif
