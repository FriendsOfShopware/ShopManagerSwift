import Foundation
import Testing
import ShopwareAdminAPI
@testable import ShopwareDomain

struct PriceTests {
    @Test(arguments: ["en_US", "de_DE"])
    func incrementalPriceInputPreservesEveryCharacter(localeID: String) {
        let locale = Locale(identifier: localeID)
        var draft = ProductPriceDraft(price: nil, locale: locale)
        for value in ["1", "11", "119"] {
            draft.updateGross(value, taxRate: 19, locale: locale)
            #expect(draft.gross == value)
        }
        #expect(ProductNumberInput.decimal(draft.net, locale: locale) == 100)
        draft.updateNet("50", taxRate: 19, locale: locale)
        #expect(ProductNumberInput.decimal(draft.gross, locale: locale) == 59.5)
    }

    @Test(arguments: ["", "-1", "NaN", "Infinity", "1,2,3", "1 000", "2.5"])
    func invalidGermanPricesNeverProducePayloads(value: String) {
        let locale = Locale(identifier: "de_DE")
        var draft = ProductPriceDraft(price: nil, locale: locale)
        draft.gross = value
        draft.net = "0"
        #expect(draft.validationError(locale: locale) != nil)
        #expect(draft.prices(replacing: [], locale: locale) == nil)
    }

    @Test func unlinkingPreventsDependentPriceChanges() {
        let locale = Locale(identifier: "en_US")
        var draft = ProductPriceDraft(price: nil, locale: locale)
        draft.linked = false
        draft.net = "7"
        draft.updateGross("119", taxRate: 19, locale: locale)
        #expect(draft.net == "7")
        draft.updateNet("8", taxRate: 19, locale: locale)
        #expect(draft.gross == "119")
    }

    @Test func updatingOneCurrencyPreservesOtherValuesAndZeroIsValid() throws {
        let locale = Locale(identifier: "de_DE")
        let original: [JSONValue] = [
            .object(["currencyId": "other", "gross": 50, "net": 40, "linked": false]),
            .object(["currencyId": .string(ShopwareDefaults.currencyID), "gross": 119, "net": 100,
                     "linked": true, "listPrice": .object(["gross": 140, "net": 120])]),
        ]
        var draft = ProductPriceDraft(price: original[1], locale: locale)
        draft.updateGross("0", taxRate: 19, locale: locale)
        let updated = try #require(draft.prices(replacing: original, locale: locale))
        #expect(updated[0] == original[0])
        #expect(updated[1]["listPrice"] == original[1]["listPrice"])
        #expect(updated[1]["gross"]?.doubleValue == 0)
        #expect(draft.validationError(locale: locale) == nil)
    }

    @Test(arguments: ["2147483648", "-2147483649", "1.5", "NaN"])
    func stockRespectsBackendIntegerRange(value: String) {
        #expect(ProductNumberInput.integer(value) == nil)
    }
}
