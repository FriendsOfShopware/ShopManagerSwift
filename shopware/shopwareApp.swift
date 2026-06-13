import SwiftUI

@main
struct shopwareApp: App {
    @State private var model = AppViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
                .tint(Theme.accent)
                .task {
                    if !model.loaded { await model.bootstrap() }
                }
        }
        #if os(macOS)
        .defaultSize(width: 1100, height: 760)
        #endif
    }
}
