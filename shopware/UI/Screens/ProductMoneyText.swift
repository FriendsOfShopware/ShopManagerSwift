import SwiftUI

struct ProductMoneyText: View {
    let amount: Double?
    let currency: String?
    var body: some View {
        if let amount, let currency { Text(amount, format: .currency(code: currency)).monospacedDigit() }
        else { Text("—").foregroundStyle(.secondary) }
    }
}
