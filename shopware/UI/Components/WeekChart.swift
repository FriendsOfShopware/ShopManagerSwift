import SwiftUI
import Charts

/// 7-day revenue bar chart with today highlighted. Labels come from `weekDayLabels` so they
/// re-localize with the app language (the snapshot stores only raw values + the sync epoch).
struct WeekChart: View {
    let data: [Double]
    let labels: [String]
    /// Index of "today" (highlighted bar) — usually 6.
    var highlight: Int = 6
    var height: CGFloat = 100

    private var points: [(day: String, value: Double, isToday: Bool)] {
        data.enumerated().map { index, value in
            (labels.indices.contains(index) ? labels[index] : "", value, index == highlight)
        }
    }

    var body: some View {
        Chart(Array(points.enumerated()), id: \.offset) { _, point in
            BarMark(
                x: .value("Day", point.day),
                y: .value("Revenue", point.value)
            )
            .foregroundStyle(point.isToday ? Theme.accent : Theme.accent.opacity(0.35))
            .cornerRadius(4)
        }
        .chartYAxis(.hidden)
        .chartXAxis {
            AxisMarks { _ in
                AxisValueLabel()
            }
        }
        .frame(height: height)
    }
}
