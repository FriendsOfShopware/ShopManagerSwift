import SwiftUI

/// Welcome screen shown before the first shop is connected — the Apple-style feature-list layout:
/// a large title, a few icon + title + description rows, and a prominent call to action.
struct OnboardingView: View {
    let onConnect: () -> Void

    private struct Feature: Identifiable {
        let id = UUID()
        let symbol: String
        let title: LocalizedStringKey
        let body: LocalizedStringKey
    }

    private let features: [Feature] = [
        Feature(symbol: "chart.line.uptrend.xyaxis",
                title: "Your shop, at a glance",
                body: "Today's revenue, open orders, and what needs attention — live from your store."),
        Feature(symbol: "shippingbox",
                title: "Manage from anywhere",
                body: "Process orders, update stock, approve reviews, and share invoices on the go."),
        Feature(symbol: "lock.shield",
                title: "Secure by design",
                body: "Sign in with your admin login. Only a rotating token is stored — never your password."),
    ]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 36) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Welcome to")
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(.secondary)
                        Text("Shopware Shop Manager")
                            .font(.largeTitle.weight(.bold))
                            .foregroundStyle(Theme.accent)
                    }
                    .padding(.top, 60)

                    VStack(alignment: .leading, spacing: 28) {
                        ForEach(features) { feature in
                            HStack(alignment: .top, spacing: 16) {
                                Image(systemName: feature.symbol)
                                    .font(.title2)
                                    .foregroundStyle(Theme.accent)
                                    .symbolRenderingMode(.hierarchical)
                                    .frame(width: 36)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(feature.title).font(.headline)
                                    Text(feature.body)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 32)
                .frame(maxWidth: 560, alignment: .leading)
                .frame(maxWidth: .infinity)
            }

            VStack(spacing: 10) {
                Button(action: onConnect) {
                    Text("Connect your shop").frame(maxWidth: 420)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)

                Text("You'll need your Shopware admin login.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
    }
}
