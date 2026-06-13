import SwiftUI
import ShopwareAdminAPI

struct ContentView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "bag.fill")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Shopware Shop Manager")
                .font(.headline)
            // Smoke-test the package link: build a criteria and show its JSON.
            Text(verbatim: smokeTest())
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    private func smokeTest() -> String {
        let criteria = Criteria()
            .setLimit(5)
            .addFilter(Criteria.equals("active", true))
        return String(decoding: criteria.toJSON().encoded(sortedKeys: true), as: UTF8.self)
    }
}

#Preview {
    ContentView()
}
