import SwiftUI

struct CustomerMetricCard: View {
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).foregroundStyle(.secondary)
            Text(value).font(.title3).bold().monospacedDigit().textSelection(.enabled)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
