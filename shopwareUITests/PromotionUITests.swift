import XCTest

@MainActor
final class PromotionUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        #if os(iOS)
        XCUIDevice.shared.orientation = .portrait
        #endif
    }
    private func launch(_ args: [String] = [], german: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--promotion-ui-fixtures", "-AppleLanguages", german ? "(de)" : "(en)", "-AppleLocale", german ? "de_DE" : "en_US", "-ApplePersistenceIgnoreState", "YES"] + args
        app.terminate()
        app.launch()
        #if os(macOS)
        app.activate()
        if !app.windows.firstMatch.waitForExistence(timeout: 5) {
            app.typeKey("n", modifierFlags: .command)
            XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 8))
        }
        #endif
        return app
    }
    private func element(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        #if os(macOS)
        // Window-scoped queries exclude duplicate Touch Bar actions and hidden menu commands.
        let inWindow = app.windows.firstMatch.descendants(matching: .any).matching(identifier: id).firstMatch
        if inWindow.exists { return inWindow }
        let menus = app.menuItems.matching(identifier: id).allElementsBoundByIndex
        if let visible = menus.first(where: { $0.isHittable }) { return visible }
        return inWindow
        #else
        return app.descendants(matching: .any).matching(identifier: id).firstMatch
        #endif
    }
    private func activate(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), element.debugDescription)
        #if os(macOS)
        element.click()
        #else
        element.tap()
        #endif
    }
    private func tap(_ id: String, _ app: XCUIApplication) { activate(element(id, app)) }
    private func wait(_ element: XCUIElement, _ predicate: String) {
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)], timeout: 12), .completed, element.debugDescription)
    }
    private func capture(_ name: String, _ app: XCUIApplication) {
        #if os(macOS)
        let attachment = XCTAttachment(screenshot: app.sheets.firstMatch.exists ? app.sheets.firstMatch.screenshot() : app.windows.firstMatch.screenshot())
        #else
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        #endif
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func section(_ name: String, _ app: XCUIApplication) { tap(name, app) }
    private func reveal(_ target: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<12 {
            let form = element("promotion.editor.form", app)
            #if os(macOS)
            let viewport = form.frame.insetBy(dx: 0, dy: 8)
            if target.exists && target.isHittable && viewport.contains(target.frame) { return }
            form.scroll(byDeltaX: 0, deltaY: target.exists && target.frame.minY < viewport.minY ? 180 : -180)
            #else
            let navigationBottom = app.navigationBars.element(boundBy: app.navigationBars.count - 1).frame.maxY
            let top = max(form.frame.minY, navigationBottom) + 20
            let bottom = min(form.frame.maxY - 30, app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY - 50 : app.frame.maxY - 40)
            if target.exists && target.isHittable && target.frame.minY >= top && target.frame.maxY <= bottom { return }
            // Keep the gesture above the keyboard, which can cover the form's
            // accessibility frame even when the field is reported as hittable.
            let scrollDown = target.exists && target.frame.minY < top
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let upper = max(top + 30, bottom - 120)
            let start = origin.withOffset(CGVector(dx: form.frame.midX, dy: scrollDown ? upper : bottom))
            let end = origin.withOffset(CGVector(dx: form.frame.midX, dy: scrollDown ? bottom : upper))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
            #endif
        }
        XCTFail("Could not reveal \(target.identifier): \(app.debugDescription)")
    }
    private func detail(_ args: [String] = [], german: Bool = false) -> XCUIApplication {
        let app = launch(["--promotion-detail"] + args, german: german)
        XCTAssertTrue(element("promotion.edit", app).waitForExistence(timeout: 15), app.debugDescription)
        return app
    }
    #if os(iOS)
    private func orientation(_ app: XCUIApplication, landscape: Bool) {
        let predicate = NSPredicate { _, _ in
            let size = app.windows.firstMatch.frame.size
            return landscape ? size.width > size.height : size.height > size.width
        }
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: predicate, object: nil)], timeout: 8), .completed)
    }
    #endif
    func testListingFiltersSearchAndAdaptiveLayout() {
        let app = launch()
        XCTAssertTrue(element("promotions.row.promotion-0", app).waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertLessThan(element("promotions.availability", app).frame.maxY, app.windows.firstMatch.frame.minY + 240)
        capture("promotions-list", app)
        #if os(iOS)
        XCUIDevice.shared.orientation = .landscapeLeft; orientation(app, landscape: true)
        capture("promotions-list-landscape", app)
        XCUIDevice.shared.orientation = .portrait; orientation(app, landscape: false)
        #endif
        tap("promotions.filters", app); tap("promotions.filter.channels", app)
        tap("entity.option.channel-2", app); tap("entity.apply", app); tap("promotions.filters.apply", app)
        XCTAssertTrue(app.staticTexts["No matching promotions"].waitForExistence(timeout: 10), app.debugDescription)
        activate(app.buttons["Clear filters"])
        XCTAssertTrue(element("promotions.row.promotion-0", app).waitForExistence(timeout: 10))
        let search = app.searchFields.firstMatch
        if !search.exists {
            let searchButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'search' OR title CONTAINS[c] 'search'")).firstMatch
            if searchButton.exists { activate(searchButton) }
        }
        activate(search); search.typeText("Winter\n")
        assertDisappears(element("promotions.row.promotion-0", app))
        tap("promotions.row.promotion-2", app)
        XCTAssertTrue(element("promotion.edit", app).waitForExistence(timeout: 10))
        section("Discounts", app)
        XCTAssertTrue(app.staticTexts["Add a discount to define how this promotion reduces the price."].waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertLessThan(element("promotion.tab.discounts", app).frame.maxY, app.windows.firstMatch.frame.minY + 240)
        capture("promotion-empty-discounts", app)
    }
    #if os(macOS)
    func testWideTable() {
        let app = launch(["--wide-table"])
        XCTAssertTrue(app.outlines.firstMatch.waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertTrue(element("promotions.row.promotion-0", app).exists)
        tap("promotions.actions", app); tap("Sort promotions", app); tap("Highest priority", app)
        wait(app.outlines.firstMatch.descendants(matching: .outlineRow).firstMatch.buttons.firstMatch, "label == 'Winter preview'")
        capture("promotions-table", app)
        tap("promotions.row.promotion-0", app)
        XCTAssertTrue(element("promotion.edit", app).waitForExistence(timeout: 10))
    }
    #endif
    func testSettingsValidationFailureAndCustomFieldRetry() {
        let app = detail(["--fail-save-once"])
        wait(element("promotion.edit", app), "enabled == true")
        capture("promotion-overview", app)
        tap("promotion.edit", app)
        let name = element("promotion.edit.name", app)
        replaceText(name, with: "Updated summer campaign")
        let priority = element("promotion.edit.priority", app)
        replaceText(priority, with: "-1", numeric: true)
        XCTAssertFalse(element("promotion.editor.save", app).isEnabled)
        replaceText(priority, with: "5", numeric: true)
        let reference = element("customField.promotion_reference", app)
        reveal(reference, app); activate(reference); reference.typeText(" updated")
        tap("promotion.editor.save", app)
        XCTAssertTrue(element("promotion.saveError", app).waitForExistence(timeout: 10))
        XCTAssertTrue((reference.value as? String ?? "").contains("updated"))
        capture("promotion-editor-retained", app)
        tap("promotion.editor.save", app)
        assertDisappears(element("promotion.editor.save", app))
        XCTAssertTrue(app.staticTexts["Updated summer campaign"].firstMatch.waitForExistence(timeout: 10))
    }
    func testDiscountAndConditionsEditors() {
        let app = detail(["--fail-discount-once", "--fail-conditions-once"])
        section("Discounts", app)
        tap("promotion.discount.edit.discount-0", app)
        replaceText(element("promotion.discount.value", app), with: "30.75", numeric: true)
        tap("promotion.editor.save", app)
        XCTAssertTrue(element("promotion.saveError", app).waitForExistence(timeout: 10))
        XCTAssertEqual(element("promotion.discount.value", app).value as? String, "30.75")
        tap("promotion.editor.save", app); assertDisappears(element("promotion.editor.save", app))
        capture("promotion-discounts", app)
        section("Conditions", app); tap("promotion.conditions.edit", app)
        tap("promotion.conditions.customer", app)
        XCTAssertFalse(element("entity.option.restricted-rule", app).isEnabled)
        tap("entity.option.rule", app); tap("entity.apply", app)
        tap("promotion.editor.save", app)
        XCTAssertTrue(element("promotion.saveError", app).waitForExistence(timeout: 10))
        tap("promotion.editor.save", app); assertDisappears(element("promotion.editor.save", app))
        XCTAssertTrue(app.staticTexts["Customers with an account"].firstMatch.waitForExistence(timeout: 10))
        capture("promotion-conditions", app)
    }
    func testCodeGenerationRetryAndSearch() {
        let app = detail(["--fail-generate-once"])
        section("Codes", app)
        XCTAssertTrue(app.staticTexts["SUMMER-A000"].firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        capture("promotion-codes-before-generation", app)
        tap("promotion.codes.generate", app)
        replaceText(element("promotion.codes.amount", app), with: "7", numeric: true)
        #if os(iOS)
        // Dismiss iPad's floating number pad before it covers the Generate action.
        activate(element("promotion.editor.form", app).staticTexts["Summer essentials"].firstMatch)
        #endif
        tap("promotion.editor.save", app)
        XCTAssertTrue(element("promotion.saveError", app).waitForExistence(timeout: 10))
        XCTAssertEqual(element("promotion.codes.amount", app).value as? String, "7")
        capture("promotion-code-generation-retained", app)
        tap("promotion.editor.save", app); assertDisappears(element("promotion.editor.save", app))
        let search = element("promotion.codes.search", app)
        activate(search); search.typeText("SUMMER-A036")
        XCTAssertTrue(app.staticTexts["SUMMER-A036"].firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        capture("promotion-codes", app)
    }
    func testAssignFirstSalesChannel() {
        let app = detail(["--unassigned-promotion"])
        section("Conditions", app)
        XCTAssertTrue(app.staticTexts["No sales channels assigned"].waitForExistence(timeout: 10))
        tap("promotion.conditions.edit", app)
        tap("promotion.conditions.channels", app)
        tap("entity.option.channel", app); tap("entity.apply", app)
        tap("promotion.editor.save", app)
        assertDisappears(element("promotion.editor.save", app))
        XCTAssertFalse(element("promotion.saveError", app).exists)
        XCTAssertFalse(app.staticTexts["No sales channels assigned"].exists)
        capture("promotion-first-sales-channel", app)
        // Reopen the editor to confirm the assignment survived the detail reload.
        tap("promotion.conditions.edit", app)
        XCTAssertTrue(element("promotion.conditions.channels", app).label.contains("1 selected"))
    }
    func testCreatePromotionAndReadOnlyGerman() {
        let app = launch()
        wait(element("promotions.create", app), "exists == true AND enabled == true")
        tap("promotions.create", app)
        replaceText(element("promotion.edit.name", app), with: "New seasonal campaign")
        tap("promotion.editor.save", app)
        assertDisappears(element("promotion.editor.save", app))
        XCTAssertTrue(app.staticTexts["New seasonal campaign"].firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        capture("promotion-created", app)
        let readOnly = detail(["--read-only", "--large-text"], german: true)
        XCTAssertFalse(element("promotion.edit", readOnly).isEnabled)
        capture("promotion-german-large-text", readOnly)
    }
    func testPartialDeleteAndListingRetry() {
        let app = launch(["--fail-list-once", "--fail-delete-promotion-2-once"])
        XCTAssertTrue(app.staticTexts["Couldn't load promotions"].waitForExistence(timeout: 10))
        activate(app.buttons["Retry"])
        XCTAssertTrue(element("promotions.row.promotion-0", app).waitForExistence(timeout: 10))
        tap("promotions.actions", app); tap("promotions.selectUnused", app)
        tap("promotions.deleteSelected", app); tap("Delete 2 promotions", app)
        XCTAssertTrue(element("Couldn't update promotions", app).waitForExistence(timeout: 10)); tap("OK", app)
        assertDisappears(element("promotions.row.promotion-0", app))
        XCTAssertTrue(element("promotions.row.promotion-2", app).exists)
        tap("promotions.deleteSelected", app); tap("Delete promotion", app)
        assertDisappears(element("promotions.row.promotion-2", app))
        tap("promotions.row.promotion-1", app); section("Discounts", app)
        XCTAssertFalse(element("promotion.discount.edit.discount-1", app).isEnabled)
        capture("promotion-redeemed-locked", app)
    }
}
