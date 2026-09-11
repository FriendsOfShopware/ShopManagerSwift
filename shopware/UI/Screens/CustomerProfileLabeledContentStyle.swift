import SwiftUI

struct CustomerProfileLabeledContentStyle: LabeledContentStyle {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    func makeBody(configuration: Configuration) -> some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 6) {
                    configuration.label.foregroundStyle(.secondary)
                    configuration.content.fixedSize(horizontal: false, vertical: true)
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 20) {
                    configuration.label.foregroundStyle(.secondary)
                    Spacer(minLength: 8)
                    configuration.content
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
