import SwiftUI

@main
struct shopwareApp: App {
    @State private var model = AppViewModel()

    init() {
        // Register the background-refresh handler before launch completes (iOS).
        let model = self.model
        BackgroundRefresh.register(model: model)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Theme.accent)
                .task {
                    if !model.loaded { await model.bootstrap() }
                    if model.data.syncEnabled { BackgroundRefresh.schedule() }
                }
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 760)
        #endif
    }
}
