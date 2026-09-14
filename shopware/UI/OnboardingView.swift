import SwiftUI

/// First launch uses the same setup steps as Add Shop, directly in the app window.
struct OnboardingView: View {
    let onFinished: (String) -> Void
    var body: some View {
        ConnectView(isFirstShop: true, onFinished: onFinished)
    }
}
