import SwiftUI

struct PromotionMoneyText: View {
    let amount: Double
    let currency: String?
    var body: some View {
        if let currency { Text(amount, format: .currency(code: currency)) }
        else { Text(amount, format: .number) }
    }
}
