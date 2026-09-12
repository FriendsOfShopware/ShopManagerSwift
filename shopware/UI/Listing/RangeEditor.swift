import SwiftUI

struct RangeEditor: View {
    @Binding var value: ClosedRangeValue

    var body: some View {
        LabeledContent("Minimum") {
            TextField("Any", value: $value.min, format: .number)
                .multilineTextAlignment(.trailing)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
        }
        LabeledContent("Maximum") {
            TextField("Any", value: $value.max, format: .number)
                .multilineTextAlignment(.trailing)
                #if os(iOS)
                .keyboardType(.decimalPad)
                #endif
        }
    }
}
