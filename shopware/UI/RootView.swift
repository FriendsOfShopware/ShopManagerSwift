import SwiftUI

/// First-shop setup lives in the window; additional shops use a sheet with the same flow.
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
                OnboardingView(onFinished: finishConnecting)
            } else {
                MainView(onAddShop: { showingConnect = true })
            }
        }
        .sheet(isPresented: $showingConnect) {
            ConnectView(
                onClose: { showingConnect = false },
                onFinished: finishConnecting
            )
            .environment(model)
        }
    }

    private func finishConnecting(_ shopId: String) {
        showingConnect = false
        model.refresh(shopId)
        model.reregisterPush()
    }
}
