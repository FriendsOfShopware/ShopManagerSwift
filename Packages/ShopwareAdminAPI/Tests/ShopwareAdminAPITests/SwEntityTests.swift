import Foundation
import Testing
@testable import ShopwareAdminAPI

// Trimmed capture of POST /api/search/order against Shopware 6.7.8.
private let orderSearch = """
{
    "total": 40,
    "data": [
        {
            "_uniqueIdentifier": "046d7824c16843b69a7c7becf49da54a",
            "versionId": "0fa91ce3e96a4bc2be4bd9ce752c3425",
            "translated": [],
            "createdAt": "2026-06-11T08:06:24.003+00:00",
            "updatedAt": null,
            "orderNumber": "11008",
            "currencyId": "b7d2554b0ce847cd82f3ac9bd1c0dfca",
            "currencyFactor": 1,
            "orderDateTime": "2026-06-11T18:44:23.000+00:00",
            "orderDate": "2026-06-11T00:00:00.000+00:00",
            "amountTotal": 2931.88,
            "amountNet": 2463.76,
            "shippingTotal": 0,
            "deepLinkCode": null,
            "autoIncrement": 8,
            "stateMachineState": {
                "_uniqueIdentifier": "019e7c5df046714bbc13a0bafa014b84",
                "translated": { "name": "Done", "customFields": [] },
                "createdAt": "2026-05-31T04:49:51.695+00:00",
                "updatedAt": null,
                "technicalName": "completed",
                "id": "019e7c5df046714bbc13a0bafa014b84",
                "apiAlias": "state_machine_state"
            },
            "currency": {
                "translated": { "name": "Euro" },
                "isoCode": "EUR",
                "factor": 1,
                "symbol": "€",
                "name": "Euro",
                "id": "b7d2554b0ce847cd82f3ac9bd1c0dfca",
                "apiAlias": "currency"
            },
            "lineItems": [
                {
                    "_uniqueIdentifier": "2094370ef2c54aed8aeefe01c60dfef9",
                    "translated": [],
                    "label": "Main product with advanced prices",
                    "quantity": 2,
                    "unitPrice": 950,
                    "totalPrice": 1900,
                    "position": 3,
                    "good": true,
                    "id": "2094370ef2c54aed8aeefe01c60dfef9",
                    "apiAlias": "order_line_item"
                }
            ],
            "billingAddress": null,
            "id": "046d7824c16843b69a7c7becf49da54a",
            "apiAlias": "order"
        }
    ],
    "aggregations": {
        "revenue": { "name": "revenue", "sum": 52855.91000000001, "apiAlias": "revenue_aggregation" },
        "orderCount": { "name": "orderCount", "count": 40, "apiAlias": "orderCount_aggregation" },
        "perDay": {
            "name": "perDay",
            "buckets": [
                { "key": "2026-06-10 00:00:00", "count": 3,
                  "dayRevenue": { "extensions": [], "name": "dayRevenue", "sum": 179.94 },
                  "apiAlias": "aggregation_bucket" },
                { "key": "2026-06-11 00:00:00", "count": 8,
                  "dayRevenue": { "extensions": [], "name": "dayRevenue", "sum": 11453.44 },
                  "apiAlias": "aggregation_bucket" }
            ],
            "apiAlias": "perDay_aggregation"
        },
        "byState": {
            "name": "byState",
            "buckets": [
                { "key": "completed", "count": 12,
                  "stateRevenue": { "extensions": [], "name": "stateRevenue", "sum": 16821.209999999995 },
                  "apiAlias": "aggregation_bucket" },
                { "key": "open", "count": 19,
                  "stateRevenue": { "extensions": [], "name": "stateRevenue", "sum": 25851.079999999994 },
                  "apiAlias": "aggregation_bucket" }
            ],
            "apiAlias": "byState_aggregation"
        }
    }
}
"""

struct SwEntityTests {
    private func result() -> SearchResult {
        SearchResult.from(JSONValue.parse(orderSearch)!)
    }

    private func order() -> SwEntity {
        result().data[0]
    }

    @Test func envelopeParsingExposesTotalDataAndAggregations() {
        let r = result()
        #expect(r.total == 40)
        #expect(r.data.count == 1)
        #expect(r.data[0].id == "046d7824c16843b69a7c7becf49da54a")
        #expect(r.aggregations["revenue"] != nil)
    }

    @Test func scalarAccessorsReadTypedValues() {
        let order = order()
        #expect(order.string("orderNumber") == "11008")
        #expect(abs(order.double("amountTotal")! - 2931.88) < 1e-9)
        #expect(order.int("autoIncrement") == 8)
        #expect(order.long("autoIncrement") == 8)
        let lineItem = order.entities("lineItems")[0]
        #expect(lineItem.boolean("good") == true)
        #expect(lineItem.int("quantity") == 2)
    }

    @Test func jsonNullFieldsAreAbsent() {
        let order = order()
        #expect(order.string("updatedAt") == nil)
        #expect(order.date("updatedAt") == nil)
        #expect(order.string("deepLinkCode") == nil)
        #expect(order.entity("billingAddress") == nil)
        #expect(order.int("missingEntirely") == nil)
    }

    @Test func translatedReadsResolvedValueWhenRootFieldAbsent() {
        let state = order().entity("stateMachineState")!
        #expect(state.string("name") == nil)
        #expect(state.translated("name") == "Done")
    }

    @Test func translatedFallsBackToRootFieldWhenTranslatedEmpty() {
        let lineItem = order().entities("lineItems")[0]
        #expect(lineItem.translated("label") == "Main product with advanced prices")
        #expect(order().entity("currency")!.translated("name") == "Euro")
    }

    @Test func instantParsesOffsetAndSpaceFormats() {
        let order = order()
        #expect(order.date("orderDateTime") == isoDate("2026-06-11T18:44:23Z"))
        #expect(order.date("createdAt") == isoDate("2026-06-11T08:06:24.003Z"))

        let spaceDates = SwEntity(JSONValue.parse(
            """
            {"bucketKey": "2026-06-10 00:00:00", "withMillis": "2026-06-11 08:21:33.000",
             "dateOnly": "2026-06-11", "garbage": "not a date"}
            """
        )!)
        #expect(spaceDates.date("bucketKey") == isoDate("2026-06-10T00:00:00Z"))
        #expect(spaceDates.date("withMillis") == isoDate("2026-06-11T08:21:33Z"))
        #expect(spaceDates.date("dateOnly") == isoDate("2026-06-11T00:00:00Z"))
        #expect(spaceDates.date("garbage") == nil)
        #expect(spaceDates.date("bucketMissing") == nil)
    }

    @Test func aggregationSumAndCountAccessors() {
        let r = result()
        #expect(abs(r.sum("revenue") - 52855.91000000001) < 1e-9)
        #expect(r.count("orderCount") == 40)
        #expect(r.sum("noSuchAggregation") == 0.0)
        #expect(r.count("noSuchAggregation") == 0)
    }

    @Test func histogramBucketsCarryDayKeysAndNestedSums() {
        let buckets = result().buckets("perDay")
        #expect(buckets.map(\.key) == ["2026-06-10 00:00:00", "2026-06-11 00:00:00"])
        #expect(buckets.map(\.count) == [3, 8])
        #expect(abs(buckets[0].sum("dayRevenue") - 179.94) < 1e-9)
        #expect(abs(buckets[1].sum() - 11453.44) < 1e-9)
    }

    @Test func termsBucketsCarryStateKeysAndNestedSums() {
        let buckets = result().buckets("byState")
        #expect(buckets.map(\.key) == ["completed", "open"])
        #expect(buckets[0].count == 12)
        #expect(abs(buckets[0].sum("stateRevenue") - 16821.209999999995) < 1e-9)
        #expect(abs(buckets[1].sum() - 25851.079999999994) < 1e-9)
        #expect(buckets[1].sum("noSuchNested") == 0.0)
        #expect(result().buckets("revenue").isEmpty)
    }

    @Test func nestedBucketsParseTermsWrappingHistogram() {
        let envelope = """
        {
          "total": 0, "data": [],
          "aggregations": {
            "byFactor": {
              "name": "byFactor",
              "buckets": [
                {"key": "1", "count": 3, "daily": {"name": "daily", "buckets": [
                  {"key": "2026-06-12 00:00:00", "count": 3, "revenue": {"name": "revenue", "sum": 300.0}}
                ]}},
                {"key": "2", "count": 1, "daily": {"name": "daily", "buckets": [
                  {"key": "2026-06-12 00:00:00", "count": 1, "revenue": {"name": "revenue", "sum": 200.0}}
                ]}}
              ]
            }
          }
        }
        """
        let r = SearchResult.from(JSONValue.parse(envelope)!)
        let factors = r.buckets("byFactor")
        #expect(factors.map(\.key) == ["1", "2"])

        let normalized = factors.reduce(0.0) { acc, fb in
            acc + fb.buckets("daily").reduce(0.0) { $0 + $1.sum("revenue") } / Double(fb.key)!
        }
        #expect(abs(normalized - 400.0) < 1e-9) // 300/1 + 200/2

        #expect(factors[0].buckets("noSuchAgg").isEmpty)
    }

    private func isoDate(_ value: String) -> Date {
        SwDate.parse(value)!
    }
}
