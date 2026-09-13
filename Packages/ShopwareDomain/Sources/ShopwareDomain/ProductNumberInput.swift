import Foundation

public enum ProductNumberInput {
    public static func decimal(_ text: String, locale: Locale) -> Double? {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let separator = locale.decimalSeparator ?? "."
        guard !text.isEmpty, text.unicodeScalars.allSatisfy({ CharacterSet.decimalDigits.contains($0) || String($0) == separator }),
              text.components(separatedBy: separator).count <= 2,
              let value = try? Double(text, format: .number.locale(locale)), value.isFinite else { return nil }
        return value
    }
    public static func integer(_ text: String) -> Int? {
        guard let value = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)), value >= Int(Int32.min), value <= Int(Int32.max) else { return nil }
        return value
    }
    public static func text(_ number: Double?, locale: Locale) -> String {
        number.map { $0.formatted(.number.grouping(.never).precision(.fractionLength(0...16)).locale(locale)) } ?? ""
    }
}
