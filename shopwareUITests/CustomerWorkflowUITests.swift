import XCTest

/// Runs the production customer screens against a fresh in-memory shop for every test.
@MainActor
final class CustomerWorkflowUITests: XCTestCase {
    private let customerName = "Alexandra Montgomery-Wellington"

    override func setUpWithError() throws {
        continueAfterFailure = false
        #if os(iOS)
        XCUIDevice.shared.orientation = .portrait
        #endif
    }

    private func launch(_ arguments: [String] = [], waitForCustomers: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--customer-ui-fixtures", "-AppleLanguages", "(en)", "-AppleLocale", "en_US"] + arguments
        #if os(macOS)
        app.launchArguments += ["-ApplePersistenceIgnoreState", "YES"]
        #endif
        app.launch()
        #if os(macOS)
        if !app.windows.firstMatch.waitForExistence(timeout: 3) {
            app.menuBarItems["File"].click()
            app.menuItems["New Window"].click()
        }
        #endif
        if waitForCustomers { XCTAssertTrue(app.staticTexts[customerName].firstMatch.waitForExistence(timeout: 15), app.debugDescription) }
        return app
    }

    private func activate(_ element: XCUIElement) {
        XCTAssertTrue(element.exists || element.waitForExistence(timeout: 8))
        #if os(macOS)
        element.click()
        #else
        element.tap()
        #endif
    }

    private func control(_ title: String, in app: XCUIApplication) -> XCUIElement {
        #if os(macOS)
        // Visible sheet actions take precedence over identically named File menu commands.
        let windowButton = app.windows.firstMatch.buttons[title].firstMatch
        if windowButton.exists && windowButton.isHittable { return windowButton }
        if app.menuButtons[title].exists { return app.menuButtons[title] }
        if app.popUpButtons[title].exists { return app.popUpButtons[title] }
        if app.radioButtons[title].exists { return app.radioButtons[title] }
        if app.menuItems[title].exists { return app.menuItems[title] }
        #endif
        return app.buttons[title]
    }

    private func tap(_ title: String, in app: XCUIApplication) { activate(control(title, in: app)) }

    private func openCustomer(_ app: XCUIApplication, name: String? = nil) {
        let row = app.staticTexts[name ?? customerName].firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 8), app.debugDescription)
        #if os(macOS)
        row.click()
        row.doubleClick()
        #else
        row.tap()
        #endif
        XCTAssertTrue(app.buttons["Edit customer"].waitForExistence(timeout: 8), app.debugDescription)
    }

    private func wait(_ element: XCUIElement, _ predicate: String, file: StaticString = #filePath, line: UInt = #line) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 8), .completed, element.debugDescription, file: file, line: line)
    }

    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<12 {
            #if os(macOS)
            if element.exists && element.isHittable { return }
            app.scrollViews.element(boundBy: app.scrollViews.count - 1).scroll(byDeltaX: 0, deltaY: -300)
            #else
            let form = app.collectionViews.count > 0
                ? app.collectionViews.element(boundBy: app.collectionViews.count - 1)
                : app.scrollViews.element(boundBy: app.scrollViews.count - 1)
            let navigationBottom = app.navigationBars.element(boundBy: app.navigationBars.count - 1).frame.maxY
            let top = max(form.frame.minY, navigationBottom) + 20
            let bottom = min(form.frame.maxY - 30, app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY - 80 : app.frame.maxY - 40)
            if element.exists && element.isHittable && element.frame.minY >= top && element.frame.maxY <= bottom { return }
            // UIKit can report fields behind the navigation bar or keyboard as hittable.
            // Keep both the field and the scrolling gesture inside the visible form area.
            let scrollDown = element.exists && element.frame.minY < top
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let upper = max(top + 30, bottom - 120)
            let start = origin.withOffset(CGVector(dx: form.frame.midX, dy: scrollDown ? upper : bottom))
            let end = origin.withOffset(CGVector(dx: form.frame.midX, dy: scrollDown ? bottom : upper))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
            #endif
        }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }

    private func replace(_ title: String, with value: String, in app: XCUIApplication) {
        let identifiers = ["First name": "customer.firstName", "Last name": "customer.lastName", "Email": "customer.email",
                           "Street": "customer.address.street", "Postal code": "customer.address.zipcode", "City": "customer.address.city",
                           "Customer number": "filter.customerNumber"]
        let field = app.textFields[identifiers[title] ?? title].firstMatch
        scrollTo(field, in: app)
        activate(field)
        #if os(macOS)
        field.typeKey("a", modifierFlags: .command)
        #else
        if let current = field.value as? String, !current.isEmpty, current != field.placeholderValue {
            field.press(forDuration: 1.1)
            let selectAll = app.menuItems["Select All"]
            XCTAssertTrue(selectAll.waitForExistence(timeout: 3), app.debugDescription)
            selectAll.tap()
        }
        #endif
        field.typeText(value)
        XCTAssertEqual(field.value as? String, value)
    }

    private func choose(_ title: String, option: String, in app: XCUIApplication) {
        let identifier = title == "Sales channel" ? "customer.salesChannel" : "customer.bulk.status"
        let picker = app.descendants(matching: .any).matching(identifier: identifier).firstMatch
        scrollTo(picker, in: app)
        activate(picker)
        tap(option, in: app)
    }

    private func openFilters(_ app: XCUIApplication) {
        #if os(iOS)
        tap("Customer list options", in: app)
        #endif
        tap("Filters", in: app)
        XCTAssertTrue(app.textFields["filter.customerNumber"].waitForExistence(timeout: 5), app.debugDescription)
    }

    private func capture(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func dismissPopover(_ app: XCUIApplication) {
        #if os(macOS)
        let cancel = app.windows.firstMatch.buttons["Cancel"].firstMatch
        if cancel.exists { activate(cancel) }
        else { app.windows.firstMatch.typeKey(.escape, modifierFlags: []) }
        #else
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.9)).tap()
        #endif
    }

    func testEditValidationSaveFailureAndReload() {
        let app = launch(["--fail-save-once"])
        openCustomer(app)
        tap("Edit customer", in: app)
        XCTAssertTrue(app.textFields["customer.firstName"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["Save"].isEnabled)
        replace("Email", with: "invalid", in: app)
        XCTAssertFalse(app.buttons["Save"].isEnabled)
        replace("Email", with: "updated@example.test", in: app)
        wait(app.buttons["Save"], "enabled == true")
        tap("Save", in: app)
        // A failed write keeps the editor and user's draft available for retry.
        let error = app.staticTexts["Fixture request failed. Please retry."]
        scrollTo(error, in: app)
        XCTAssertTrue(error.exists)
        capture("customer-save-retry")
        tap("Save", in: app)
        wait(app.buttons["Save"], "exists == false")
        tap("Refresh customer", in: app)
        #if os(iOS)
        XCTAssertTrue(app.staticTexts["updated@example.test"].firstMatch.waitForExistence(timeout: 8))
        #endif
        tap("Edit customer", in: app)
        XCTAssertTrue(app.textFields["customer.email"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.textFields["customer.email"].value as? String, "updated@example.test")
        XCTAssertFalse(app.buttons["Save"].isEnabled)
    }

    func testCreateCustomerWithRequiredFields() {
        let app = launch()
        tap("Add customer", in: app)
        XCTAssertTrue(app.textFields["Customer number"].waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertFalse(app.buttons["customer.create.save"].isEnabled)
        choose("Sales channel", option: "Storefront", in: app)
        let guest = app.descendants(matching: .any).matching(identifier: "customer.guest").firstMatch
        activate(guest.switches.firstMatch.exists ? guest.switches.firstMatch : guest)
        replace("First name", with: "Taylor", in: app)
        replace("Last name", with: "Morgan", in: app)
        replace("Email", with: "taylor@example.test", in: app)
        replace("Street", with: "42 Test Street", in: app)
        replace("Postal code", with: "10115", in: app)
        XCTAssertFalse(app.buttons["customer.create.save"].isEnabled)
        replace("City", with: "Berlin", in: app)
        wait(app.buttons["customer.create.save"], "enabled == true")
        activate(app.buttons["customer.create.save"])
        XCTAssertTrue(app.buttons["Edit customer"].waitForExistence(timeout: 8), app.debugDescription)
        tap("Refresh customer", in: app)
        XCTAssertTrue(app.staticTexts["Taylor Morgan"].firstMatch.waitForExistence(timeout: 8))
        // iOS combines LabeledContent's label and value into one accessibility element.
        let number = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "SW10044", "SW10044")).firstMatch
        XCTAssertTrue(number.waitForExistence(timeout: 8))
        tap("Addresses", in: app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "42 Test Street", "42 Test Street")).firstMatch.waitForExistence(timeout: 8))
        capture("customer-created")
    }

    func testDeleteCustomerRequiresConfirmation() {
        let app = launch()
        openCustomer(app)
        tap("Customer actions", in: app)
        tap("Delete customer", in: app)
        XCTAssertTrue(app.buttons["customer.delete.confirm"].firstMatch.waitForExistence(timeout: 5))
        dismissPopover(app)
        XCTAssertTrue(app.buttons["Edit customer"].isEnabled)
        tap("Customer actions", in: app)
        tap("Delete customer", in: app)
        activate(app.buttons["customer.delete.confirm"].firstMatch)
        XCTAssertTrue(app.staticTexts["Sam Rivera"].firstMatch.waitForExistence(timeout: 8))
        wait(app.staticTexts[customerName].firstMatch, "exists == false")
        capture("customer-deleted")
    }

    func testAddressEditPersistsAndDefaultCannotBeDeleted() {
        let app = launch()
        openCustomer(app)
        tap("Addresses", in: app)
        tap("Address actions", in: app)
        XCTAssertFalse(control("Delete address", in: app).isEnabled)
        tap("Edit", in: app)
        XCTAssertTrue(app.textFields["customer.address.street"].waitForExistence(timeout: 8))
        replace("Street", with: "456 Updated Avenue", in: app)
        wait(app.buttons["Save"], "enabled == true")
        tap("Save", in: app)
        wait(app.buttons["Save"], "exists == false")
        let address = app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "456 Updated Avenue", "456 Updated Avenue")).firstMatch
        XCTAssertTrue(address.waitForExistence(timeout: 8))
        tap("Address actions", in: app)
        XCTAssertFalse(control("Delete address", in: app).isEnabled)
        tap("Edit", in: app)
        XCTAssertTrue(app.textFields["customer.address.street"].waitForExistence(timeout: 8))
        XCTAssertEqual(app.textFields["customer.address.street"].value as? String, "456 Updated Avenue")
        XCTAssertFalse(app.buttons["Save"].isEnabled)
    }

    func testBulkEditRetriesFailedCustomers() {
        let app = launch(["--fail-bulk-once"])
        #if os(macOS)
        activate(app.staticTexts[customerName].firstMatch)
        XCUIElement.perform(withKeyModifiers: .command) { app.staticTexts["Sam Rivera"].firstMatch.click() }
        #else
        tap("Customer list options", in: app)
        tap("Select customers", in: app)
        activate(app.staticTexts[customerName].firstMatch)
        activate(app.staticTexts["Sam Rivera"].firstMatch)
        #endif
        XCTAssertTrue(app.staticTexts["2 selected"].exists)
        tap("Edit selected", in: app)
        choose("Status", option: "Active", in: app)
        activate(app.buttons["customer.bulk.apply"])
        activate(app.buttons["customer.bulk.confirm"].firstMatch)
        XCTAssertTrue(app.staticTexts["1 completed; 1 failed."].waitForExistence(timeout: 8), app.debugDescription)
        capture("customer-bulk-partial-failure")
        activate(app.buttons["customer.bulk.apply"])
        activate(app.buttons["customer.bulk.confirm"].firstMatch)
        XCTAssertTrue(app.staticTexts["2 completed; 0 failed."].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["customer.bulk.apply"].isEnabled)
        tap("Close", in: app)
        #if os(iOS)
        tap("Customer list options", in: app)
        tap("Done selecting", in: app)
        openCustomer(app, name: "Sam Rivera")
        #else
        // Verify the customer whose first request failed, using the table's context action.
        let retriedCustomer = app.staticTexts["Sam Rivera"].firstMatch
        XCTAssertTrue(retriedCustomer.waitForExistence(timeout: 8))
        retriedCustomer.click()
        retriedCustomer.rightClick()
        tap("Open customer", in: app)
        #endif
        XCTAssertTrue(app.staticTexts["Active"].firstMatch.waitForExistence(timeout: 8))
    }

    func testReadOnlyPermissionsDisableCustomerActions() {
        let app = launch(["--read-only"])
        XCTAssertFalse(app.buttons["Add customer"].isEnabled)
        openCustomer(app)
        XCTAssertFalse(app.buttons["Edit customer"].isEnabled)
        tap("Customer actions", in: app)
        XCTAssertFalse(control("Delete customer", in: app).isEnabled)
        XCTAssertFalse(control("Log in as customer", in: app).isEnabled)
        dismissPopover(app)
        tap("Addresses", in: app)
        XCTAssertFalse(app.buttons["Add address"].isEnabled)
        tap("Orders", in: app)
        XCTAssertTrue(app.staticTexts["Order access unavailable"].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["Create order…"].exists)
        capture("customer-read-only")
    }

    func testListingAndPermissionFailuresCanBeRetried() {
        let app = launch(["--fail-list-once", "--fail-permissions-once"], waitForCustomers: false)
        XCTAssertTrue(app.staticTexts["Fixture request failed. Please retry."].waitForExistence(timeout: 8))
        XCTAssertFalse(app.buttons["Add customer"].isEnabled)
        #if os(macOS)
        activate(app.buttons["Retry"].firstMatch)
        #else
        tap("Retry permissions", in: app)
        #endif
        wait(app.buttons["Add customer"], "enabled == true")
        tap("Retry", in: app)
        XCTAssertTrue(app.staticTexts[customerName].firstMatch.waitForExistence(timeout: 8))
        XCTAssertFalse(app.staticTexts["Fixture request failed. Please retry."].exists)
    }

    func testCustomerFilterApplyAndReset() {
        let app = launch()
        openFilters(app)
        replace("Customer number", with: "SW10043", in: app)
        #if os(iOS)
        app.textFields["filter.customerNumber"].typeText("\n")
        #endif
        capture("customer-filter-draft")
        tap("Apply", in: app)
        wait(app.textFields["filter.customerNumber"], "exists == false")
        wait(app.staticTexts[customerName].firstMatch, "exists == false")
        XCTAssertTrue(app.staticTexts["Sam Rivera"].firstMatch.exists)
        openFilters(app)
        XCTAssertEqual(app.textFields["filter.customerNumber"].value as? String, "SW10043")
        tap("Reset", in: app)
        XCTAssertTrue(app.staticTexts[customerName].firstMatch.waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["Sam Rivera"].firstMatch.exists)
    }
}
