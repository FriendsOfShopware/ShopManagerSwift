import XCTest

@MainActor
final class OrderUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        #if os(iOS)
        XCUIDevice.shared.orientation = .portrait
        #endif
    }
    private func launch(_ arguments: [String] = [], german: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--order-ui-fixtures", "-AppleLanguages", german ? "(de)" : "(en)", "-AppleLocale", german ? "de_DE" : "en_US", "-ApplePersistenceIgnoreState", "YES"] + arguments
        app.launch()
        #if os(macOS)
        if !app.windows.firstMatch.waitForExistence(timeout: 3) {
            app.menuBarItems[german ? "Ablage" : "File"].click()
            app.menuItems[german ? "Neues Fenster" : "New Window"].click()
        }
        #endif
        if arguments.contains("--order-detail") { XCTAssertTrue(app.buttons["order.edit"].waitForExistence(timeout: 15), app.debugDescription) }
        return app
    }
    private func activate(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), element.debugDescription)
        #if os(macOS)
        element.click()
        #else
        element.tap()
        #endif
    }
    private func control(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        #if os(macOS)
        for query in [app.windows.firstMatch.buttons, app.menuButtons, app.popUpButtons, app.menuItems, app.radioButtons] {
            let result = query[id].firstMatch
            if result.exists && result.isHittable { return result }
        }
        #endif
        return app.buttons[id].firstMatch
    }
    private func tap(_ id: String, _ app: XCUIApplication) { activate(control(id, app)) }
    private func wait(_ element: XCUIElement, _ predicate: String) {
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)], timeout: 12), .completed, element.debugDescription)
    }
    private func capture(_ name: String) {
        #if os(macOS)
        let app = XCUIApplication()
        let attachment = XCTAttachment(screenshot: app.sheets.firstMatch.exists ? app.sheets.firstMatch.screenshot() : app.windows.firstMatch.screenshot())
        #else
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        #endif
        attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
    }
    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            #if os(macOS)
            let scroll = app.sheets.firstMatch.exists ? app.sheets.firstMatch.scrollViews.firstMatch : (app.scrollViews["order.overview"].exists ? app.scrollViews["order.overview"] : app.scrollViews["order.details"])
            scroll.scroll(byDeltaX: 0, deltaY: -220)
            #else
            let scroll = app.collectionViews.allElementsBoundByIndex.first { $0.isHittable }
                ?? app.scrollViews.allElementsBoundByIndex.first { $0.isHittable } ?? app.scrollViews.firstMatch
            scroll.swipeUp()
            #endif
        }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }
    private func section(_ name: String, _ app: XCUIApplication) { tap(name, app) }

    #if os(iOS)
    private func waitForOrientation(_ app: XCUIApplication, landscape: Bool) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let size = app.windows.firstMatch.frame.size
            return landscape ? size.width > size.height : size.height > size.width
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 8), .completed)
    }
    #endif

    func testListingSearchAndOpenOrder() {
        let app = launch()
        XCTAssertTrue(app.staticTexts["#10001"].firstMatch.waitForExistence(timeout: 15), app.debugDescription)
        capture("orders-list")
        #if os(iOS)
        XCUIDevice.shared.orientation = .landscapeLeft
        waitForOrientation(app, landscape: true)
        capture("orders-list-landscape")
        XCUIDevice.shared.orientation = .portrait
        waitForOrientation(app, landscape: false)
        #endif
        let search = app.searchFields.firstMatch
        activate(search); search.typeText("Rivera")
        XCTAssertTrue(app.staticTexts["#10002"].firstMatch.waitForExistence(timeout: 10))
        wait(app.staticTexts["#10001"].firstMatch, "exists == false")
        capture("orders-search")
        #if os(macOS)
        if app.tables.firstMatch.exists { app.staticTexts["#10002"].firstMatch.doubleClick() }
        else { tap("orders.row.order-1", app) }
        #else
        tap("orders.row.order-1", app)
        #endif
        XCTAssertTrue(app.buttons["order.edit"].waitForExistence(timeout: 10))
        XCTAssertTrue(app.staticTexts["Sam Rivera"].firstMatch.waitForExistence(timeout: 10))
        capture("order-overview")
    }

    func testEmptyDocumentsAndActivityKeepSectionsAtTop() {
        let app = launch(["--order-detail", "--empty-details"])
        let documents = control("Documents", app)
        XCTAssertTrue(documents.waitForExistence(timeout: 15), app.debugDescription)
        let top = documents.frame.midY
        section("Documents", app)
        XCTAssertTrue(app.staticTexts["No documents yet"].waitForExistence(timeout: 10))
        XCTAssertEqual(control("Documents", app).frame.midY, top, accuracy: 2)
        capture("order-empty-documents")
        section("Activity", app)
        XCTAssertTrue(app.staticTexts["No activity yet"].waitForExistence(timeout: 10))
        XCTAssertEqual(control("Documents", app).frame.midY, top, accuracy: 2)
        capture("order-empty-activity")
        #if os(iOS)
        XCUIDevice.shared.orientation = .landscapeLeft
        waitForOrientation(app, landscape: true)
        XCTAssertLessThan(control("Documents", app).frame.maxY, app.windows.firstMatch.frame.minY + 220)
        capture("order-empty-activity-landscape")
        XCUIDevice.shared.orientation = .portrait
        waitForOrientation(app, landscape: false)
        #endif
        section("Details", app)
        XCTAssertTrue(app.buttons["order.tracking.delivery-order-0"].waitForExistence(timeout: 10))
        capture("order-details")
    }

    func testEditRetainsDraftAfterFailureAndRequiresReview() {
        let app = launch(["--order-detail", "--fail-save-once"])
        tap("order.edit", app)
        let email = app.textFields["order.editor.email"]
        reveal(email, app); activate(email); email.typeText(".changed")
        let draft = email.value as? String
        tap("order.editor.save", app)
        XCTAssertTrue(app.staticTexts["Fixture request failed. Please retry."].firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(email.value as? String, draft)
        capture("order-edit-retained")
        tap("order.editor.save", app)
        wait(app.buttons["Save changes"].firstMatch, "enabled == true")
        capture("order-edit-review")
        tap("order.editor.save", app)
        wait(app.buttons["order.editor.save"], "exists == false")
        capture("order-edited")
    }

    func testNoteAndTrackingRetainDraftAndRefresh() {
        let app = launch(["--order-detail", "--fail-tracking-once"])
        section("Details", app)
        let tracking = app.buttons["order.tracking.delivery-order-0"]
        reveal(tracking, app); activate(tracking)
        let codes = app.textFields["order.tracking.codes"]
        activate(codes); codes.typeText("4")
        let value = codes.value as? String
        tap("order.editor.save", app)
        XCTAssertTrue(app.staticTexts["Fixture request failed. Please retry."].firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(codes.value as? String, value)
        capture("order-tracking-retained")
        tap("order.editor.save", app)
        wait(app.buttons["order.editor.save"], "exists == false")
        let note = app.buttons["order.note.edit"]
        reveal(note, app); activate(note)
        let text = app.textFields["order.note.text"]
        activate(text); text.typeText(" Ready to ship.")
        tap("order.editor.save", app)
        wait(app.buttons["order.editor.save"], "exists == false")
        capture("order-notes")
    }

    func testDocumentGenerationErrorRemainsInSheet() {
        let app = launch(["--order-detail", "--fail-document-once"])
        section("Documents", app)
        tap("Generate document…", app)
        let number = app.textFields["order.document.number"]
        activate(number); number.typeText("INV-NEW")
        tap("order.editor.save", app)
        XCTAssertTrue(app.staticTexts["Document fixture rejected the settings."].firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertEqual(number.value as? String, "INV-NEW")
        capture("order-document-error")
        tap("order.editor.save", app)
        wait(app.buttons["order.editor.save"], "exists == false")
        XCTAssertTrue(app.staticTexts["INV-NEW"].waitForExistence(timeout: 10))
        capture("order-documents")
    }

    func testBulkDeletionKeepsFailedOrdersForRetry() {
        let app = launch(["--fail-delete-once"])
        XCTAssertTrue(app.buttons["orders.create"].waitForExistence(timeout: 15))
        tap("orders.actions", app); tap("Select loaded orders", app)
        tap("orders.actions", app); tap("Delete selected orders…", app)
        let apply = app.buttons["orders.bulk.apply"]
        wait(apply, "enabled == true")
        activate(apply); tap("orders.bulk.confirm", app)
        XCTAssertTrue(app.staticTexts["1 order remaining"].waitForExistence(timeout: 12), app.debugDescription)
        capture("order-bulk-partial-delete")
        activate(apply); tap("orders.bulk.confirm", app)
        XCTAssertTrue(app.staticTexts["0 orders remaining"].waitForExistence(timeout: 12))
        tap("orders.bulk.done", app)
        XCTAssertTrue(app.staticTexts["No orders yet"].waitForExistence(timeout: 12))
        capture("orders-empty")
    }

    func testNativeDocumentPreview() {
        let app = launch(["--order-detail"])
        section("Documents", app)
        tap("order.document.preview.invoice-order-0", app)
        #if os(macOS)
        let preview = app.windows["Quick Look"]
        XCTAssertTrue(preview.waitForExistence(timeout: 12), app.debugDescription)
        XCTAssertTrue(preview.buttons["QLControlShare"].exists)
        let attachment = XCTAttachment(screenshot: preview.screenshot())
        attachment.name = "order-document-preview"; attachment.lifetime = .keepAlways; add(attachment)
        activate(preview.buttons["close panel button"])
        #else
        let close = app.buttons["QLOverlayDoneButtonAccessibilityIdentifier"]
        XCTAssertTrue(close.waitForExistence(timeout: 12), app.debugDescription)
        XCTAssertTrue(app.staticTexts["Order invoice preview"].waitForExistence(timeout: 10))
        capture("order-document-preview")
        activate(close)
        #endif
    }

    private func toggle(_ id: String, _ app: XCUIApplication) {
        activate(app.descendants(matching: .any)[id].firstMatch)
    }

    func testStatusFailureRetainsOptionsAndUpdatesActivity() {
        let app = launch(["--order-detail", "--fail-status-once"])
        let state = control("order.state.order-0", app)
        reveal(state, app); activate(state)
        tap("order.transition.order-0.process", app)
        toggle("order.transition.email", app)
        let comment = app.textFields["order.transition.comment"]
        activate(comment); comment.typeText("Ready for fulfillment")
        tap("order.transition.apply", app)
        XCTAssertTrue(app.staticTexts["Fixture request failed. Please retry."].firstMatch.waitForExistence(timeout: 10))
        XCTAssertEqual(comment.value as? String, "Ready for fulfillment")
        capture("order-status-retained")
        tap("order.transition.apply", app)
        wait(app.buttons["order.transition.apply"], "exists == false")
        section("Activity", app)
        XCTAssertTrue(app.descendants(matching: .any)["order.activity.history-0"].firstMatch.waitForExistence(timeout: 10), app.debugDescription)
        capture("order-activity")
    }

    func testCreateOrderThroughSharedCustomerCart() {
        let app = launch()
        let create = app.buttons["orders.create"]
        XCTAssertTrue(create.waitForExistence(timeout: 15)); wait(create, "enabled == true")
        activate(create)
        tap("entity.option.customer", app); tap("entity.apply", app)
        let products = app.buttons["order.create.products"]
        reveal(products, app); activate(products)
        tap("entity.option.product", app); tap("entity.apply", app)
        let email = app.descendants(matching: .any)["order.create.email"].firstMatch
        reveal(email, app); activate(email)
        let review = app.buttons["order.create.review"]
        wait(review, "enabled == true")
        capture("order-create-review")
        activate(review); tap("order.create.confirm", app)
        XCTAssertTrue(app.buttons["order.edit"].waitForExistence(timeout: 15), app.debugDescription)
        let item = app.descendants(matching: .any)["order.item.product"].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 10), app.debugDescription)
        XCTAssertTrue(item.label.contains("Ceramic mug"), item.debugDescription)
        capture("order-created")
    }

    func testGermanLargeTextReadOnly() {
        let app = launch(["--order-detail", "--read-only", "--large-text"], german: true)
        let edit = app.buttons["order.edit"]
        XCTAssertTrue(edit.waitForExistence(timeout: 15))
        XCTAssertFalse(edit.isEnabled)
        capture("order-german-large-overview")
        // At accessibility sizes the segmented control becomes a labeled menu.
        tap("order.sections", app)
        tap("Details", app)
        capture("order-german-large-details")
    }
}
