import WidgetKit
import SwiftUI

/// The widget extension's bundle: the today-sales hero and the weekly bar chart, both reading the
/// shared App Group cache written by the app (`WidgetData`).
@main
struct ShopwareWidgetBundle: WidgetBundle {
    var body: some Widget {
        SalesWidget()
        WeeklySalesWidget()
    }
}

// MARK: - Today sales

struct SalesEntry: TimelineEntry {
    let date: Date
    let state: WidgetState?
}

struct SalesProvider: TimelineProvider {
    func placeholder(in context: Context) -> SalesEntry {
        SalesEntry(date: Date(), state: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (SalesEntry) -> Void) {
        completion(SalesEntry(date: Date(), state: WidgetData.readSelectedShopSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SalesEntry>) -> Void) {
        let entry = SalesEntry(date: Date(), state: WidgetData.readSelectedShopSnapshot())
        // Refresh roughly every 30 min; the app also reloads timelines on sync/select.
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct SalesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "SalesWidget", provider: SalesProvider()) { entry in
            SalesWidgetView(state: entry.state)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Sales today")
        .description("Today's revenue for your selected shop.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Weekly sales

struct WeeklyEntry: TimelineEntry {
    let date: Date
    let state: WeeklyWidgetState?
}

struct WeeklyProvider: TimelineProvider {
    func placeholder(in context: Context) -> WeeklyEntry {
        WeeklyEntry(date: Date(), state: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (WeeklyEntry) -> Void) {
        completion(WeeklyEntry(date: Date(), state: WidgetData.readWeeklySnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeeklyEntry>) -> Void) {
        let entry = WeeklyEntry(date: Date(), state: WidgetData.readWeeklySnapshot())
        let next = Calendar.current.date(byAdding: .minute, value: 30, to: Date()) ?? Date().addingTimeInterval(1800)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct WeeklySalesWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "WeeklySalesWidget", provider: WeeklyProvider()) { entry in
            WeeklySalesWidgetView(state: entry.state)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("This week")
        .description("Your 7-day revenue and trend.")
        .supportedFamilies([.systemMedium])
    }
}
