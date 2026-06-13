import Testing
@testable import ShopwareAdminAPI

struct CriteriaTests {
    private func assertGolden(_ expected: String, _ criteria: Criteria) {
        let expectedValue = JSONValue.parse(expected)
        #expect(expectedValue == criteria.toJSON())
    }

    @Test func emptyCriteriaEmitsEmptyObject() {
        assertGolden("{}", Criteria())
    }

    @Test func dashboardStyleQuery() {
        let criteria = Criteria()
            .setLimit(1)
            .addFilter(Criteria.equals("order.stateMachineState.technicalName", "open"))
            .addFilter(Criteria.range("orderDateTime", gte: "2026-06-01 00:00:00"))
            .addFilter(Criteria.not("and", Criteria.equals("customerComment", nil)))
            .addSorting("orderDateTime", "DESC")
            .addAggregation(
                Criteria.histogram(
                    "order_count_day", "orderDateTime", interval: "day",
                    aggregation: Criteria.sum("totalAmount", "amountTotal")
                )
            )

        assertGolden(
            """
            {
              "limit": 1,
              "filter": [
                {"type": "equals", "field": "order.stateMachineState.technicalName", "value": "open"},
                {"type": "range", "field": "orderDateTime", "parameters": {"gte": "2026-06-01 00:00:00"}},
                {"type": "not", "operator": "and", "queries": [
                  {"type": "equals", "field": "customerComment", "value": null}
                ]}
              ],
              "sort": [{"field": "orderDateTime", "order": "DESC"}],
              "aggregations": [
                {
                  "name": "order_count_day",
                  "type": "histogram",
                  "field": "orderDateTime",
                  "interval": "day",
                  "aggregation": {"name": "totalAmount", "type": "sum", "field": "amountTotal"}
                }
              ]
            }
            """,
            criteria
        )
    }

    @Test func termsAggregationWithNestedSumAndCountSort() {
        let criteria = Criteria()
            .setLimit(0)
            .addAggregation(
                Criteria.terms(
                    "products", "lineItems.productId",
                    limit: 5,
                    sort: Criteria.sort("_count", "DESC"),
                    aggregation: Criteria.sum("revenue", "lineItems.totalPrice")
                )
            )

        assertGolden(
            """
            {
              "limit": 0,
              "aggregations": [
                {
                  "name": "products",
                  "type": "terms",
                  "field": "lineItems.productId",
                  "limit": 5,
                  "sort": {"field": "_count", "order": "DESC"},
                  "aggregation": {"name": "revenue", "type": "sum", "field": "lineItems.totalPrice"}
                }
              ]
            }
            """,
            criteria
        )
    }

    @Test func dotPathAssociationExpandsNestedCriteria() {
        let criteria = Criteria()
            .addAssociation("deliveries.shippingMethod")
            .addAssociation("deliveries.shippingOrderAddress")
            .addAssociation("transactions")

        assertGolden(
            """
            {
              "associations": {
                "deliveries": {
                  "associations": {
                    "shippingMethod": {},
                    "shippingOrderAddress": {}
                  }
                },
                "transactions": {}
              }
            }
            """,
            criteria
        )
    }

    @Test func getAssociationAllowsConfiguringNestedCriteria() {
        let criteria = Criteria()
        criteria.getAssociation("lineItems").setLimit(10).addSorting("position")

        assertGolden(
            """
            {
              "associations": {
                "lineItems": {
                  "limit": 10,
                  "sort": [{"field": "position", "order": "ASC"}]
                }
              }
            }
            """,
            criteria
        )
    }

    @Test func includesAndTotalCountMode() {
        let criteria = Criteria()
            .setPage(2)
            .setLimit(25)
            .setTotalCountMode(.exact)
            .addIncludes("order", ["id", "orderNumber", "amountTotal"])
            .addIncludes("state_machine_state", ["name", "technicalName"])

        assertGolden(
            """
            {
              "page": 2,
              "limit": 25,
              "total-count-mode": 1,
              "includes": {
                "order": ["id", "orderNumber", "amountTotal"],
                "state_machine_state": ["name", "technicalName"]
              }
            }
            """,
            criteria
        )
    }

    @Test func equalsAnyAndNullEquals() {
        let criteria = Criteria()
            .setTerm("hoodie")
            .setIds(["0190", "0191"])
            .setTotalCountMode(.none)
            .addFilter(Criteria.equalsAny("stateId", ["aaa", "bbb"]))
            .addFilter(Criteria.equals("parentId", nil))
            .addFilter(Criteria.equals("active", true))
            .addFilter(Criteria.equals("stock", .int(0)))

        assertGolden(
            """
            {
              "term": "hoodie",
              "ids": ["0190", "0191"],
              "total-count-mode": 0,
              "filter": [
                {"type": "equalsAny", "field": "stateId", "value": ["aaa", "bbb"]},
                {"type": "equals", "field": "parentId", "value": null},
                {"type": "equals", "field": "active", "value": true},
                {"type": "equals", "field": "stock", "value": 0}
              ]
            }
            """,
            criteria
        )
    }

    @Test func textAndMultiFilters() {
        let criteria = Criteria()
            .addFilter(
                Criteria.multi(
                    "or",
                    Criteria.contains("name", "shirt"),
                    Criteria.prefix("productNumber", "SW-"),
                    Criteria.suffix("name", "XL")
                )
            )
            .addFilter(Criteria.range("stock", lte: .int(100), gt: .int(0)))

        assertGolden(
            """
            {
              "filter": [
                {"type": "multi", "operator": "or", "queries": [
                  {"type": "contains", "field": "name", "value": "shirt"},
                  {"type": "prefix", "field": "productNumber", "value": "SW-"},
                  {"type": "suffix", "field": "name", "value": "XL"}
                ]},
                {"type": "range", "field": "stock", "parameters": {"lte": 100, "gt": 0}}
              ]
            }
            """,
            criteria
        )
    }
}
