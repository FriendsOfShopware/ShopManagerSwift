import Foundation

/// Currency + delta formatting. Money is formatted from the shop's `locale.code` and currency —
/// never hardcode locale or currency (mirrors the Android `fmtMoney`/`ConnectedShop.fmt`).
enum Format {
    static func currencySymbol(_ iso: String) -> String {
        let locale = Locale(identifier: "en_GB")
        return locale.localizedCurrencySymbol(forCurrencyCode: iso) ?? iso
    }

    /// Whole-number currency string (no fraction digits), matching the Android dashboard style.
    static func money(_ amount: Double, currencyIso: String = "EUR", localeTag: String? = nil) -> String {
        let locale = localeTag.map { Locale(identifier: $0.replacingOccurrences(of: "-", with: "_")) }
            ?? Locale(identifier: "en_GB")
        var fmt = amount.formatted(
            .currency(code: currencyIso)
                .locale(locale)
                .precision(.fractionLength(0))
        )
        if fmt.isEmpty { fmt = currencySymbol(currencyIso) + String(Int(amount.rounded())) }
        return fmt
    }

    /// Compact currency (e.g. "€1.2K", "€3.4M") for chart/bar labels.
    static func moneyCompact(_ amount: Double, currencyIso: String = "EUR", localeTag: String? = nil) -> String {
        let locale = localeTag.map { Locale(identifier: $0.replacingOccurrences(of: "-", with: "_")) }
            ?? Locale(identifier: "en_GB")
        let symbol = currencySymbol(currencyIso)
        let abs = Swift.abs(amount)
        let (scaled, suffix): (Double, String) = switch abs {
        case 1_000_000...: (amount / 1_000_000, "M")
        case 1_000...: (amount / 1_000, "K")
        default: (amount, "")
        }
        let digits = suffix.isEmpty ? 0 : 1
        let number = scaled.formatted(.number.locale(locale).precision(.fractionLength(0...digits)))
        return "\(symbol)\(number)\(suffix)"
    }

    static func delta(today: Double, yesterday: Double) -> Delta {
        let pct: Int
        if yesterday <= 0 {
            pct = today > 0 ? 100 : 0
        } else {
            pct = Int(((today - yesterday) * 100.0 / yesterday).rounded())
        }
        return Delta(pct: pct, up: pct >= 0, label: "\(pct >= 0 ? "+" : "")\(pct)%")
    }
}

extension ConnectedShop {
    /// Money in this shop's currency and locale.
    func fmt(_ amount: Double) -> String {
        Format.money(amount, currencyIso: currency, localeTag: localeCode)
    }
}

private extension Locale {
    func localizedCurrencySymbol(forCurrencyCode code: String) -> String? {
        // Build a minimal currency format and extract the symbol, falling back to the code.
        let formatted = (0.0).formatted(.currency(code: code).locale(self).precision(.fractionLength(0)))
        let stripped = formatted.filter { !$0.isNumber && $0 != "." && $0 != "," && !$0.isWhitespace }
        return stripped.isEmpty ? nil : stripped
    }
}
