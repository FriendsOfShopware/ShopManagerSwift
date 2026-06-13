import SwiftUI

/// 3-page intro carousel shown before the first shop is connected.
struct OnboardingView: View {
    let onConnect: () -> Void
    @State private var page = 0

    private struct Page: Identifiable {
        let id = UUID()
        let symbol: String
        let title: LocalizedStringKey
        let body: LocalizedStringKey
    }

    private let pages: [Page] = [
        Page(symbol: "chart.line.uptrend.xyaxis",
             title: "Your shop, on the go",
             body: "Track today's revenue, open orders, and what needs attention — live from your Shopware store."),
        Page(symbol: "shippingbox",
             title: "Manage from anywhere",
             body: "Process orders, update stock, approve reviews, and share invoices right from your pocket."),
        Page(symbol: "lock.shield",
             title: "Secure by design",
             body: "Sign in with your admin login. Only a rotating refresh token is stored — never your password."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                ForEach(Array(pages.enumerated()), id: \.offset) { index, page in
                    VStack(spacing: 20) {
                        Image(systemName: page.symbol)
                            .font(.system(size: 72))
                            .foregroundStyle(Theme.accent)
                            .symbolRenderingMode(.hierarchical)
                        Text(page.title)
                            .font(.title.bold())
                            .multilineTextAlignment(.center)
                        Text(page.body)
                            .font(.body)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                    }
                    .tag(index)
                }
            }
            #if os(iOS)
            .tabViewStyle(.page(indexDisplayMode: .always))
            #endif
            .frame(maxHeight: .infinity)

            Button(action: onConnect) {
                Text("Connect your shop")
                    .frame(maxWidth: 360)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
            .padding(.bottom, 40)
            .padding(.horizontal)
        }
    }
}
