import Foundation

/// Models carry raw epoch millis so timestamps re-localize with the app language; `epochMs <= 0`
/// means "unknown" (legacy persisted snapshots) and reads as "just now".
func relativeAgoText(_ epochMs: Int64, nowMs: Int64 = Date().epochMs) -> String {
    let mins = max(0, (nowMs - epochMs) / 60_000)
    if epochMs <= 0 || mins < 1 {
        return String(localized: "Just now")
    } else if mins < 60 {
        return String(localized: "\(Int(mins)) min ago")
    } else if mins < 60 * 24 {
        return String(localized: "\(Int(mins / 60)) h ago")
    } else if mins < 60 * 24 * 7 {
        let days = Int(mins / (60 * 24))
        return String(localized: "^[\(days) day](inflect: true) ago")
    } else {
        let weeks = Int(mins / (60 * 24 * 7))
        return String(localized: "^[\(weeks) week](inflect: true) ago")
    }
}

/// The snapshot's week revenue always covers the 7 days ending on the sync date, so the axis labels
/// are derived here in the current app language instead of being persisted as formatted strings.
func weekDayLabels(endEpochMs: Int64) -> [String] {
    var cal = Calendar.current
    cal.timeZone = .current
    let end = endEpochMs > 0
        ? Date(timeIntervalSince1970: Double(endEpochMs) / 1000)
        : Date()

    let formatter = DateFormatter()
    formatter.locale = Locale.current
    formatter.setLocalizedDateFormatFromTemplate("EEE")

    return (0...6).reversed().map { offset in
        let day = cal.date(byAdding: .day, value: -offset, to: end)!
        return formatter.string(from: day)
    }
}
