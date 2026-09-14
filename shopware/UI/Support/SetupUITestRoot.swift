#if DEBUG
import SwiftUI

struct SetupUITestRoot: View {
    @State private var model: AppViewModel
    @State private var vm: ConnectViewModel
    @State private var additionalSetup: AdditionalSetup?
    @State private var finished = false
    private let arguments = ProcessInfo.processInfo.arguments

    private struct AdditionalSetup: Identifiable {
        let id = UUID()
        let viewModel: ConnectViewModel
    }

    init() {
        let repo = AppRepository(directory: FileManager.default.temporaryDirectory.appendingPathComponent("setup-ui-\(UUID())"))
        _model = State(initialValue: AppViewModel(repo: repo))
        _vm = State(initialValue: ConnectViewModel(repo: repo,
            transport: SetupUITestTransport(arguments: ProcessInfo.processInfo.arguments), encrypt: { "fixture-encrypted:\($0)" }))
    }

    var body: some View {
        Group {
            if finished {
                VStack(spacing: 24) {
                    Text(verbatim: model.data.shops.first?.name ?? "").accessibilityIdentifier("setup.completed")
                    Button("Connect a shop") {
                        additionalSetup = AdditionalSetup(viewModel: ConnectViewModel(repo: model.repo,
                            transport: SetupUITestTransport(), encrypt: { "fixture-encrypted:\($0)" }))
                    }.accessibilityIdentifier("setup.addShop")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ConnectView(isFirstShop: true, onFinished: { _ in finished = true }, viewModel: vm)
            }
        }
        .sheet(item: $additionalSetup) { setup in
            ConnectView(onClose: { additionalSetup = nil }, onFinished: { _ in additionalSetup = nil }, viewModel: setup.viewModel)
        }
        .environment(model)
        .dynamicTypeSize(arguments.contains("--large-text") ? .accessibility3 : .large)
        .preferredColorScheme(arguments.contains("--dark") ? .dark : .light)
        #if os(macOS)
        .background(AppUITestWindowPlacement())
        #endif
    }
}

#Preview("Setup") { SetupUITestRoot().tint(Theme.accent) }
#endif
