#if os(iOS)
import XCTest

@MainActor
final class CustomerUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        XCUIDevice.shared.orientation = .portrait
    }

    private func launch(_ arguments: [String] = [], language: String = "en") -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--customer-ui-fixtures", "-AppleLanguages", "(\(language))", "-AppleLocale", language == "de" ? "de_DE" : "en_US"] + arguments
        app.launch()
        XCTAssertTrue(app.staticTexts["Alexandra Montgomery-Wellington"].firstMatch.waitForExistence(timeout: 15), app.debugDescription)
        return app
    }

    private func capture(_ name: String, app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func openCustomer(_ app: XCUIApplication) {
        app.staticTexts["Alexandra Montgomery-Wellington"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Edit customer"].waitForExistence(timeout: 10), app.debugDescription)
    }

    func testCustomerNavigationAndForms() throws {
        let app = launch()
        capture("customer-list-portrait", app: app)
        openCustomer(app)
        capture("customer-profile-portrait", app: app)
        XCUIDevice.shared.orientation = .landscapeLeft
        let landscape = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            app.frame.width > app.frame.height
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [landscape], timeout: 5), .completed)
        app.swipeUp()
        capture("customer-profile-landscape", app: app)
        XCUIDevice.shared.orientation = .portrait

        app.buttons["Edit customer"].tap()
        let firstName = app.textFields["customer.firstName"]
        XCTAssertTrue(firstName.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["Save"].isEnabled)
        firstName.tap()
        firstName.typeText(" Test")
        capture("customer-edit-keyboard", app: app)
        app.buttons["Cancel"].tap()
        XCTAssertTrue(app.buttons["Discard changes"].waitForExistence(timeout: 5))
        app.buttons["Discard changes"].tap()
        XCTAssertTrue(app.buttons["Edit customer"].waitForExistence(timeout: 5))

        app.buttons["Addresses"].tap()
        XCTAssertTrue(app.buttons["Address actions"].firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        capture("customer-addresses", app: app)
        app.buttons["Address actions"].firstMatch.tap()
        XCTAssertFalse(app.buttons["Delete address"].isEnabled)
        app.buttons["Edit"].tap()
        XCTAssertTrue(app.textFields["customer.address.street"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["Save"].isEnabled)
        capture("customer-address-edit", app: app)
        app.buttons["Cancel"].tap()

        app.buttons["Orders"].tap()
        XCTAssertTrue(app.staticTexts["#10042"].waitForExistence(timeout: 10), app.debugDescription)
        capture("customer-orders", app: app)
        app.buttons["Create order…"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Currency,")).firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertFalse(app.buttons["Create order"].isEnabled)
        capture("customer-order-create", app: app)
        for _ in 0..<4 where !app.buttons["Add products…"].isHittable {
            app.collectionViews.element(boundBy: app.collectionViews.count - 1).swipeUp()
        }
        XCTAssertTrue(app.buttons["Add products…"].isHittable, app.debugDescription)
        capture("customer-order-items", app: app)
        app.buttons["Close"].tap()
        XCTAssertTrue(app.buttons["Create order…"].waitForExistence(timeout: 5))
    }

    func testSelectionAndSearch() throws {
        let app = launch()
        app.buttons["Customer list options"].tap()
        app.buttons["Select customers"].tap()
        XCTAssertFalse(app.buttons["Edit selected"].isEnabled)
        app.staticTexts["Alexandra Montgomery-Wellington"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["1 selected"].exists)
        XCTAssertTrue(app.buttons["Edit selected"].isEnabled)
        capture("customer-selection", app: app)
        app.buttons["Edit selected"].tap()
        XCTAssertTrue(app.buttons["Close"].waitForExistence(timeout: 10), app.debugDescription)
        capture("customer-bulk-edit", app: app)
        app.buttons["Close"].tap()
        app.buttons["Customer list options"].tap()
        app.buttons["Done selecting"].tap()
        let search = app.searchFields.firstMatch
        if !search.isHittable { app.swipeDown() }
        search.tap()
        search.typeText("no-matching-customer\n")
        XCTAssertTrue(app.staticTexts["No customers found"].waitForExistence(timeout: 10), app.debugDescription)
        capture("customer-search-empty", app: app)
    }

    func testAccessibilityAndEmptyOrders() throws {
        let app = launch(["--large-text", "--empty-orders"])
        capture("customer-list-accessibility", app: app)
        openCustomer(app)
        capture("customer-profile-accessibility", app: app)
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "Customer section")).firstMatch.tap()
        app.buttons["Orders"].tap()
        XCTAssertTrue(app.staticTexts["No orders yet"].waitForExistence(timeout: 10), app.debugDescription)
        capture("customer-orders-empty-accessibility", app: app)
        XCTAssertTrue(app.buttons["Create order…"].isHittable)
    }


    func testGermanCustomerLocalization() throws {
        let app = launch(language: "de")
        XCTAssertTrue(app.staticTexts["2 Kunden"].exists, app.debugDescription)
        XCTAssertTrue(app.staticTexts["Inaktiver Kunde"].exists)
        capture("customer-list-german", app: app)
        app.buttons["Optionen der Kundenliste"].tap()
        app.buttons["Filter"].tap()
        XCTAssertTrue(app.staticTexts["Kundennummer"].firstMatch.waitForExistence(timeout: 5), app.debugDescription)
        capture("customer-filters-german", app: app)
        app.buttons["Anwenden"].tap()

        let search = app.searchFields.firstMatch
        search.tap()
        search.typeText("SW10042\n")
        XCTAssertTrue(app.staticTexts["1 Kunde"].waitForExistence(timeout: 5), app.debugDescription)
        capture("customer-count-singular-german", app: app)
        app.staticTexts["Alexandra Montgomery-Wellington"].firstMatch.tap()
        XCTAssertTrue(app.buttons["Kunde bearbeiten"].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(app.buttons["Allgemein"].exists)
        capture("customer-profile-german", app: app)
        app.buttons["Adressen"].tap()
        XCTAssertTrue(app.buttons["Adresse hinzufügen"].waitForExistence(timeout: 5))
        capture("customer-addresses-german", app: app)
        app.buttons["Bestellungen"].tap()
        XCTAssertTrue(app.staticTexts["Bestellhistorie"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Bestellung erstellen …"].isHittable)
        capture("customer-orders-german", app: app)
    }

    func testNarrowLayout() throws {
        let app = launch(["--narrow-window"])
        openCustomer(app)
        capture("customer-profile-narrow", app: app)
        app.buttons["Orders"].tap()
        XCTAssertTrue(app.staticTexts["#10042"].waitForExistence(timeout: 10), app.debugDescription)
        capture("customer-orders-narrow", app: app)
    }
}
#endif
