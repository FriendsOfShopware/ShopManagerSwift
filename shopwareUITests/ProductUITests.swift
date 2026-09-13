import XCTest

@MainActor
final class ProductUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        #if os(iOS)
        XCUIDevice.shared.orientation = .portrait
        #endif
    }
    private func launch(_ args: [String] = [], german: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--product-ui-fixtures", "-AppleLanguages", german ? "(de)" : "(en)", "-AppleLocale", german ? "de_DE" : "en_US", "-ApplePersistenceIgnoreState", "YES"] + args
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
        let button = app.buttons.matching(identifier: id).firstMatch
        if button.exists { return button }
        let matches = app.descendants(matching: .any).matching(identifier: id)
        return matches.allElementsBoundByIndex.first { $0.isHittable } ?? matches.firstMatch
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
    private func tap(_ id: String, _ app: XCUIApplication) {
        #if os(iOS)
        // iPad moves a compact sheet when its decimal keypad becomes the full
        // keyboard. Dismiss the keyboard before querying the toolbar's position.
        if id == "product.editor.save", app.buttons["Hide keyboard"].exists, app.buttons["Hide keyboard"].isHittable {
            activate(app.buttons["Hide keyboard"])
        }
        #endif
        activate(element(id, app))
    }
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
    private func section(_ name: String, _ app: XCUIApplication) {
        if !app.buttons[name].firstMatch.isHittable { tap("product.section", app) }
        tap(name, app)
    }
    private func reveal(_ target: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<12 {
            let form = element("product.editor.form", app)
            #if os(macOS)
            let viewport = form.frame.insetBy(dx: 0, dy: 8)
            if target.exists && target.isHittable && viewport.contains(target.frame) { return }
            form.scroll(byDeltaX: 0, deltaY: target.exists && target.frame.minY < viewport.minY ? 180 : -180)
            #else
            let navigationBottom = app.navigationBars.element(boundBy: app.navigationBars.count - 1).frame.maxY
            let top = max(form.frame.minY, navigationBottom) + 20
            let bottom = min(form.frame.maxY - 30, app.keyboards.firstMatch.exists ? app.keyboards.firstMatch.frame.minY - 50 : app.frame.maxY - 40)
            if target.exists && target.isHittable && target.frame.minY >= top && target.frame.maxY <= bottom { return }
            // Drag the form's gutter, above the keyboard. Dragging through a
            // focused price field can move its caret instead of scrolling.
            let scrollDown = target.exists && target.frame.minY < top
            let origin = app.coordinate(withNormalizedOffset: .zero)
            let upper = max(top + 30, bottom - 120)
            let start = origin.withOffset(CGVector(dx: form.frame.minX + 8, dy: scrollDown ? upper : bottom))
            let end = origin.withOffset(CGVector(dx: form.frame.minX + 8, dy: scrollDown ? bottom : upper))
            start.press(forDuration: 0.05, thenDragTo: end, withVelocity: .slow, thenHoldForDuration: 0.2)
            #endif
        }
        XCTFail("Could not reveal \(target.identifier): \(app.debugDescription)")
    }
    private func detail(_ args: [String] = [], german: Bool = false) -> XCUIApplication {
        let app = launch(["--product-detail"] + args, german: german)
        XCTAssertTrue(element("product.edit", app).waitForExistence(timeout: 15), app.debugDescription)
        return app
    }
    #if os(iOS)
    private func dismissPriceKeyboard(_ app: XCUIApplication) {
        let done = app.buttons["product.price.done"].firstMatch
        // An iPad sheet can have a compact size class too. Its Done accessory
        // remains visible when the native keyboard is already offscreen.
        if done.exists && app.windows.firstMatch.frame.intersects(done.frame) {
            if !done.isHittable {
                // The decimal popover intercepts the first outside tap. Use
                // the visible accessory, not the offscreen full keyboard.
                done.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                let dismissedPopover = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
                    done.isHittable || !app.keyboards.firstMatch.exists
                }, object: nil)
                XCTAssertEqual(XCTWaiter.wait(for: [dismissedPopover], timeout: 10), .completed)
            }
            if done.exists && done.isHittable { activate(done) }
        } else if UIDevice.current.userInterfaceIdiom == .pad {
            let hide = app.keyboards.buttons["Hide keyboard"].firstMatch
            XCTAssertTrue(hide.waitForExistence(timeout: 10))
            // iPad presents decimal input in a popover over the full keyboard.
            // Its outside-tap dismissal must happen before keyboard controls
            // become hittable again.
            if !hide.isHittable {
                XCTAssertTrue(app.windows.firstMatch.frame.intersects(hide.frame))
                hide.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
            }
            if app.keyboards.firstMatch.exists { activate(hide) }
            // Hiding the full keyboard can leave the compact accessory behind.
            if done.exists && done.isHittable { activate(done) }
        } else {
            activate(done)
        }
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 10))
    }
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
        XCTAssertTrue(element("products.row.product-0", app).waitForExistence(timeout: 15), app.debugDescription)
        XCTAssertLessThan(element("products.availability", app).frame.maxY, app.windows.firstMatch.frame.minY + 240)
        capture("products-list", app)
        #if os(iOS)
        XCUIDevice.shared.orientation = .landscapeLeft; orientation(app, landscape: true)
        capture("products-list-landscape", app)
        XCUIDevice.shared.orientation = .portrait; orientation(app, landscape: false)
        #endif
        tap("products.filters", app); tap("products.filter.salesChannel", app)
        tap("entity.option.outlet", app); tap("entity.apply", app); tap("products.filters.apply", app)
        XCTAssertTrue(app.staticTexts["No matching products"].waitForExistence(timeout: 10))
        activate(app.buttons["Clear filters"])
        let search = app.searchFields.firstMatch
        if !search.exists {
            let button = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'search' OR title CONTAINS[c] 'search'")).firstMatch
            if button.exists { activate(button) }
        }
        activate(search); search.typeText("Ceramic\n")
        assertDisappears(element("products.row.product-0", app))
        tap("products.row.product-2", app)
        XCTAssertTrue(element("product.edit", app).waitForExistence(timeout: 10))
        tap("product.actions", app)
        tap("Refresh product", app)
        wait(element("product.edit", app), "enabled == true")
        capture("product-overview", app)
        section("Inventory", app)
        capture("product-inventory", app)
    }
    func testQuickEditRetainsStockAfterFailure() {
        let app = launch(["--product-quick", "--fail-save-once"])
        let stock = element("product.quick.stock", app)
        replaceText(stock, with: "47", incrementally: true)
        tap("product.editor.save", app)
        XCTAssertTrue(element("product.saveError", app).waitForExistence(timeout: 10))
        XCTAssertEqual(stock.value as? String, "47")
        capture("product-quick-editor", app)
        tap("product.editor.save", app)
        assertDisappears(element("product.editor.save", app))
    }
    func testCreateProductWithTaxAndPrice() {
        let app = launch(["--empty-products", "--disable-ui-animations"])
        tap("products.create", app)
        replaceText(element("product.edit.name", app), with: "Summer linen shirt", incrementally: true)
        replaceText(element("product.edit.number", app), with: "SUMMER-100", incrementally: true)
        #if os(iOS)
        app.typeText("\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 10))
        #endif
        let tax = element("product.edit.tax", app)
        reveal(tax, app); activate(tax)
        tap("Standard rate", app)
        // Complete ordinary fields before decimal input. The compact iPad
        // keyboard can leave stale accessibility frames while the sheet moves.
        let stock = element("product.edit.stock", app)
        reveal(stock, app); replaceText(stock, with: "8", incrementally: true)
        #if os(iOS)
        app.typeText("\n")
        XCTAssertTrue(app.keyboards.firstMatch.waitForNonExistence(timeout: 10))
        #endif
        let gross = element("product.price.gross", app)
        reveal(gross, app); replaceText(gross, with: "119", incrementally: true)
        #if os(iOS)
        dismissPriceKeyboard(app)
        #endif
        capture("product-create", app)
        tap("product.editor.save", app)
        assertDisappears(element("product.editor.save", app))
        XCTAssertTrue(app.staticTexts["Summer linen shirt"].firstMatch.waitForExistence(timeout: 10))
    }
    func testGeneralValidationAndFailedSaveRetainsChanges() {
        let app = detail(["--fail-save-once"])
        wait(element("product.edit", app), "enabled == true")
        tap("product.edit", app)
        let name = element("product.edit.name", app)
        replaceText(name, with: "")
        XCTAssertFalse(element("product.editor.save", app).isEnabled)
        replaceText(name, with: "Updated linen shirt")
        tap("product.editor.save", app)
        XCTAssertTrue(element("product.saveError", app).waitForExistence(timeout: 10))
        XCTAssertEqual(name.value as? String, "Updated linen shirt")
        capture("product-editor-retained", app)
        tap("product.editor.save", app)
        assertDisappears(element("product.editor.save", app))
        XCTAssertTrue(app.staticTexts["Updated linen shirt"].firstMatch.waitForExistence(timeout: 10))
    }
    func testInventoryAndCurrencyPriceEditing() {
        let app = detail(["--fail-save-once", "--disable-ui-animations"])
        section("Inventory", app); tap("product.inventory.edit", app)
        let stock = element("product.inventory.stock", app)
        replaceText(stock, with: "42", incrementally: true)
        tap("product.editor.save", app)
        XCTAssertTrue(element("product.saveError", app).waitForExistence(timeout: 10))
        XCTAssertEqual(stock.value as? String, "42")
        tap("product.editor.save", app); assertDisappears(element("product.editor.save", app))
        section("Pricing", app)
        tap("product.price.edit.b7d2554b0ce847cd82f3ac9bd1c0dfca", app)
        replaceText(element("product.price.gross", app), with: "51.25", incrementally: true)
        capture("product-price-editor", app)
        #if os(iOS)
        dismissPriceKeyboard(app)
        #endif
        tap("product.editor.save", app)
        assertDisappears(element("product.editor.save", app))
        capture("product-prices", app)
        tap("product.price.edit.b7d2554b0ce847cd82f3ac9bd1c0dfca", app)
        XCTAssertEqual(element("product.price.gross", app).value as? String, "51.25")
    }
    func testAssignmentsAndMedia() {
        let app = detail(["--fail-assignments-once"])
        let assignments = element("product.organization.edit", app)
        // The assignments section follows the description in the overview form.
        if !assignments.isHittable {
            #if os(macOS)
            element("product.overview", app).scroll(byDeltaX: 0, deltaY: -250)
            #else
            element("product.overview", app).swipeUp()
            #endif
        }
        activate(assignments)
        tap("product.organization.salesChannels", app); tap("entity.option.outlet", app); tap("entity.apply", app)
        tap("product.editor.save", app)
        XCTAssertTrue(element("product.saveError", app).waitForExistence(timeout: 10))
        tap("product.editor.save", app); assertDisappears(element("product.editor.save", app))
        section("Media", app)
        tap("product.media.add", app); tap("product.media.choose", app)
        tap("entity.option.image-2", app); tap("entity.apply", app)
        let mapping = "product.media.cover." + "ec0a5aed1fdb03bc3975fe0fc2c6206d"
        XCTAssertTrue(element(mapping, app).waitForExistence(timeout: 10))
        tap(mapping, app)
        wait(element(mapping, app), "enabled == false")
        capture("product-media", app)
    }
    func testVariantsPagingAndReadOnlyGermanLayout() {
        let app = detail(["--many-variants"])
        section("Variants", app)
        XCTAssertTrue(element("product.variants.loadMore", app).waitForExistence(timeout: 10))
        let search = element("product.variants.search", app)
        activate(search); search.typeText("SW-100-131")
        XCTAssertTrue(element("product.variant.variant-131", app).waitForExistence(timeout: 10))
        tap("product.variant.variant-131", app)
        XCTAssertTrue(app.staticTexts["SW-100-131"].firstMatch.waitForExistence(timeout: 10))
        capture("product-variant", app)
        let readOnly = detail(["--read-only", "--large-text"], german: true)
        XCTAssertFalse(element("product.edit", readOnly).isEnabled)
        capture("product-german-large-text", readOnly)
    }
    #if os(macOS)
    func testWideTableAndBulkFailureRetry() {
        let app = launch(["--wide-table", "--fail-delete-product-2-once"])
        XCTAssertTrue(app.outlines.firstMatch.waitForExistence(timeout: 15))
        capture("products-table", app)
        tap("products.actions", app); tap("products.selectAll", app)
        tap("products.selection.actions", app); tap("Delete products…", app); tap("Delete 3 products", app)
        XCTAssertTrue(element("Couldn't update products", app).waitForExistence(timeout: 10)); tap("OK", app)
        assertDisappears(element("products.row.product-0", app))
        tap("products.selection.actions", app); tap("Delete products…", app); tap("Delete product", app)
        XCTAssertTrue(app.staticTexts["No products yet"].waitForExistence(timeout: 10))
    }
    #endif
}
