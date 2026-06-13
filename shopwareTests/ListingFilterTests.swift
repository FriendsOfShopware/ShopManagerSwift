import Foundation
import Testing
import ShopwareAdminAPI
@testable import shopware

@MainActor
struct ListingFilterTests {
    private func assertGolden(_ expected: String, _ filter: ListingFilter, _ value: FilterValue) {
        let produced = JSONValue.array(filter.criteria(for: value))
        #expect(JSONValue.parse(expected) == produced)
    }

    /// A UTC date at midnight for the given y/m/d (the analogue of LocalDate in the pinned-UTC test).
    private func utcDate(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: year, month: month, day: day))!
    }

    @Test func optionsProducesEqualsAnyOnField() {
        assertGolden(
            #"[{"type": "equalsAny", "field": "salesChannel.id", "value": ["a1", "b2"]}]"#,
            .options(key: "salesChannel", label: "Sales channel", field: "salesChannel.id"),
            .options(["a1", "b2"])
        )
    }

    @Test func salesChannelFilterFieldPaths() {
        assertGolden(
            #"[{"type": "equalsAny", "field": "salesChannelId", "value": ["a1"]}]"#,
            salesChannelFilter(label: "Sales channel"),
            .options(["a1"])
        )
        assertGolden(
            #"[{"type": "equalsAny", "field": "salesChannels.salesChannelId", "value": ["a1"]}]"#,
            salesChannelFilter(label: "Sales channel", field: "salesChannels.salesChannelId"),
            .options(["a1"])
        )
    }

    @Test func numberRangeProducesRangeWithGteLte() {
        assertGolden(
            #"[{"type": "range", "field": "amountTotal", "parameters": {"gte": 100.0, "lte": 500.0}}]"#,
            .numberRange(key: "amount", label: "Amount", field: "amountTotal"),
            .range(min: 100.0, max: 500.0)
        )
    }

    @Test func numberRangeOmitsUnsetBound() {
        assertGolden(
            #"[{"type": "range", "field": "amountTotal", "parameters": {"gte": 100.0}}]"#,
            .numberRange(key: "amount", label: "Amount", field: "amountTotal"),
            .range(min: 100.0, max: nil)
        )
    }

    @Test func dateRangeUsesDayStartAndExclusiveNextDayInstants() {
        assertGolden(
            """
            [{
                "type": "range",
                "field": "orderDateTime",
                "parameters": {"gte": "2026-01-01T00:00:00Z", "lt": "2026-02-01T00:00:00Z"}
            }]
            """,
            .dateRange(key: "orderDate", label: "Order date", field: "orderDateTime"),
            .dateRange(from: utcDate(2026, 1, 1), to: utcDate(2026, 1, 31))
        )
    }

    @Test func existenceHasProducesNotEqualsNull() {
        assertGolden(
            """
            [{"type": "not", "operator": "and", "queries": [
                {"type": "equals", "field": "documents.id", "value": null}
            ]}]
            """,
            .existence(key: "documents", label: "Documents", field: "documents.id", hasLabel: "Has documents", hasNotLabel: "No documents"),
            .existence(true)
        )
    }

    @Test func existenceHasNotProducesEqualsNull() {
        assertGolden(
            #"[{"type": "equals", "field": "documents.id", "value": null}]"#,
            .existence(key: "documents", label: "Documents", field: "documents.id", hasLabel: "Has documents", hasNotLabel: "No documents"),
            .existence(false)
        )
    }

    @Test func textModes() {
        let value = FilterValue.text("shirt")
        assertGolden(#"[{"type": "contains", "field": "name", "value": "shirt"}]"#,
                     .text(key: "name", label: "Name", field: "name", mode: .contains), value)
        assertGolden(#"[{"type": "equals", "field": "name", "value": "shirt"}]"#,
                     .text(key: "name", label: "Name", field: "name", mode: .equals), value)
        assertGolden(#"[{"type": "prefix", "field": "name", "value": "shirt"}]"#,
                     .text(key: "name", label: "Name", field: "name", mode: .prefix), value)
    }

    @Test func boolProducesEqualsWithBooleanValue() {
        let filter = ListingFilter.bool(key: "status", label: "Status", field: "status", trueLabel: "Approved", falseLabel: "Pending")
        assertGolden(#"[{"type": "equals", "field": "status", "value": true}]"#, filter, .options(["true"]))
        assertGolden(#"[{"type": "equals", "field": "status", "value": false}]"#, filter, .options(["false"]))
    }

    @Test func boolWithoutSingleSelectionProducesNoCriteria() {
        let filter = ListingFilter.bool(key: "status", label: "Status", field: "status", trueLabel: "Approved", falseLabel: "Pending")
        #expect(filter.criteria(for: .options([])).isEmpty)
        #expect(filter.criteria(for: .options(["true", "false"])).isEmpty)
    }

    @Test func emptyValuesProduceNoCriteria() {
        #expect(ListingFilter.options(key: "state", label: "State", field: "stateMachineState.id")
            .criteria(for: .options([])).isEmpty)
        #expect(ListingFilter.text(key: "name", label: "Name", field: "name")
            .criteria(for: .text("  ")).isEmpty)
        #expect(ListingFilter.numberRange(key: "amount", label: "Amount", field: "amountTotal")
            .criteria(for: .range(min: nil, max: nil)).isEmpty)
        #expect(ListingFilter.dateRange(key: "date", label: "Date", field: "orderDateTime")
            .criteria(for: .dateRange(from: nil, to: nil)).isEmpty)
        #expect(ListingFilter.existence(key: "docs", label: "Docs", field: "documents.id", hasLabel: "Has", hasNotLabel: "Has not")
            .criteria(for: .existence(nil)).isEmpty)
    }

    @Test func mismatchedValueTypeProducesNoCriteria() {
        let options = ListingFilter.options(key: "state", label: "State", field: "stateMachineState.id")
        #expect(options.criteria(for: .text("open")).isEmpty)
    }
}
