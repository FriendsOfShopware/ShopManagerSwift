import Foundation
import SwiftUI

// Live analytics results for the Reports tab — fetched on demand, never persisted to the snapshot.
// Modeled on the official Shopware Analytics app (SwagAnalytics); the 12 KPIs achievable through
// the Admin API.

/// One point in a date histogram.
struct TimePoint: Equatable, Sendable, Identifiable {
    var epochMs: Int64
    var value: Double
    var id: Int64 { epochMs }
}

/// A time-series KPI with a headline total and the prior equal-length window total for a delta.
struct TimeSeriesKpi: Equatable, Sendable {
    var points: [TimePoint]
    var total: Double
    var previousTotal: Double?
    var isMoney: Bool
}

/// One row of a terms breakdown (top-N). `value` is what the bar encodes (revenue or quantity).
struct BreakdownRow: Equatable, Sendable, Identifiable {
    var id: String
    var label: String
    var value: Double
    var secondary: Double?
}

/// A terms-breakdown KPI (horizontal bars). `valueIsMoney` drives formatting of `value`.
struct BreakdownKpi: Equatable, Sendable {
    var rows: [BreakdownRow]
    var valueIsMoney: Bool
}

/// A single headline number with an optional prior-window value for a delta.
struct SingleKpi: Equatable, Sendable {
    var value: Double
    var previousValue: Double?
    var isMoney: Bool
}

/// The 12 Admin-API KPIs (order roughly follows SwagAnalytics' kpi-registry positions).
enum KpiType: String, CaseIterable, Identifiable, Sendable {
    case totalSales, orderCount, avgOrderValue, newCustomers
    case salesChannel, paymentMethod, shippingMethod, country
    case bestSellingProduct, manufacturer, promotionCode
    case customerCount

    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .totalSales: "Total sales"
        case .orderCount: "Orders"
        case .avgOrderValue: "Average order value"
        case .newCustomers: "New customers"
        case .salesChannel: "By sales channel"
        case .paymentMethod: "By payment method"
        case .shippingMethod: "By shipping method"
        case .country: "By country"
        case .bestSellingProduct: "Best sellers"
        case .manufacturer: "By manufacturer"
        case .promotionCode: "Promotion codes"
        case .customerCount: "Total customers"
        }
    }
}

/// Per-card state so each KPI loads/fails independently.
enum KpiState: Equatable, Sendable {
    case loading
    case error(String)
    case timeSeries(TimeSeriesKpi)
    case breakdown(BreakdownKpi)
    case single(SingleKpi)
}

// MARK: - Filters

enum HistogramInterval: String, Sendable {
    case day, week, month
    var apiValue: String { rawValue }
}

/// A resolved date window in epoch millis [fromMs, toMs). `preset` is for the UI chip selection.
struct DateRange: Equatable, Sendable {
    enum Preset: String, CaseIterable, Sendable, Identifiable {
        case today, last7, last30, last90, custom
        var id: String { rawValue }
        var label: LocalizedStringKey {
            switch self {
            case .today: "Today"
            case .last7: "7 days"
            case .last30: "30 days"
            case .last90: "90 days"
            case .custom: "Custom"
            }
        }
    }

    var preset: Preset
    var fromMs: Int64
    var toMs: Int64

    /// day buckets for short ranges, week beyond a month, month beyond a quarter.
    var interval: HistogramInterval {
        let days = (toMs - fromMs) / 86_400_000
        switch days {
        case ...31: return .day
        case ...92: return .week
        default: return .month
        }
    }
}

struct AnalyticsFilters: Equatable, Sendable {
    var dateRange: DateRange
    var salesChannelIds: [String] = []
    var orderStateIds: [String] = []      // stateMachineState.technicalName
    var paymentStateIds: [String] = []    // transactions.stateMachineState.technicalName
    var deliveryStateIds: [String] = []   // deliveries.stateMachineState.technicalName
    var customerGroupIds: [String] = []
    var countryIds: [String] = []

    /// Number of non-date filters active (for the "Filters (n)" chip).
    var activeCount: Int {
        salesChannelIds.count + orderStateIds.count + paymentStateIds.count +
            deliveryStateIds.count + customerGroupIds.count + countryIds.count
    }
}

/// An id/label option for the analytics filter sheet.
struct FilterOptionItem: Equatable, Sendable, Identifiable {
    var id: String
    var label: String
}

/// The options driving the analytics filter sheet (states keyed by which order-relation they filter).
struct AnalyticsFilterOptions: Equatable, Sendable {
    var salesChannels: [FilterOptionItem] = []
    var customerGroups: [FilterOptionItem] = []
    var countries: [FilterOptionItem] = []
    var orderStates: [FilterOptionItem] = []      // stateMachine = order.state
    var paymentStates: [FilterOptionItem] = []    // order_transaction.state
    var deliveryStates: [FilterOptionItem] = []   // order_delivery.state
}
