import SwiftUI

/// Top-level routing: onboarding → connect wizard → main app, mirroring the Android NavHost.
struct RootView: View {
    @Environment(AppViewModel.self) private var model
    @State private var showingConnect = false

    var body: some View {
        Group {
            if !model.loaded {
                ProgressView()
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.data.shops.isEmpty {
                OnboardingView(onConnect: { showingConnect = true })
            } else {
                MainView(onAddShop: { showingConnect = true })
            }
        }
        .sheet(isPresented: $showingConnect) {
            ConnectView(
                onClose: { showingConnect = false },
                onFinished: { shopId in
                    showingConnect = false
                    model.refresh(shopId)
                }
            )
            .environment(model)
        }
    }
}
