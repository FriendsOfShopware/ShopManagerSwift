import XCTest

@MainActor
final class ReviewUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        #if os(iOS)
        XCUIDevice.shared.orientation = .portrait
        #endif
    }
    private func launch(_ args: [String] = [], german: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--review-ui-fixtures", "-AppleLanguages", german ? "(de)" : "(en)", "-AppleLocale", german ? "de_DE" : "en_US", "-ApplePersistenceIgnoreState", "YES"] + args
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
    private func openReview(_ id: String, _ app: XCUIApplication) {
        let row = element("reviews.row.\(id)", app)
        XCTAssertTrue(row.waitForExistence(timeout: 15), app.debugDescription)
        activate(row)
        XCTAssertTrue(element("review.title", app).waitForExistence(timeout: 10), app.debugDescription)
    }
    private func reveal(_ element: XCUIElement, _ app: XCUIApplication, earlier: Bool = false) {
        for _ in 0..<6 {
            if element.exists && element.isHittable { return }
            #if os(macOS)
            let scroll = app.sheets.firstMatch.exists ? app.sheets.firstMatch.scrollViews.firstMatch : app.scrollViews["review.detail"].firstMatch
            scroll.scroll(byDeltaX: 0, deltaY: earlier ? 240 : -180)
            #else
            let scroll = app.collectionViews.allElementsBoundByIndex.first { $0.isHittable } ?? app.scrollViews.firstMatch
            if earlier { scroll.swipeDown() } else { scroll.swipeUp() }
            #endif
        }
    }

    func testListingFilterSearchAndAdaptiveLayout() {
        let app = launch()
        XCTAssertTrue(element("reviews.row.review-0", app).waitForExistence(timeout: 15), app.debugDescription)
        let approval = element("reviews.approval", app)
        XCTAssertLessThan(approval.frame.maxY, app.windows.firstMatch.frame.minY + 230)
        capture("reviews-list", app)
        #if os(iOS)
        XCUIDevice.shared.orientation = .landscapeLeft
        waitOrientation(app, landscape: true)
        XCTAssertLessThan(element("reviews.approval", app).frame.maxY, app.windows.firstMatch.frame.minY + 230)
        capture("reviews-list-landscape", app)
        XCUIDevice.shared.orientation = .portrait
        waitOrientation(app, landscape: false)
        #endif
        tap("reviews.filters", app)
        tap("reviews.filter.language", app)
        tap("entity.option.de", app); tap("entity.apply", app)
        tap("reviews.filters.apply", app)
        XCTAssertTrue(app.staticTexts["No matching reviews"].waitForExistence(timeout: 10), app.debugDescription)
        capture("reviews-filtered-empty", app)
        activate(app.buttons["Clear filters"])
        XCTAssertTrue(element("reviews.row.review-0", app).waitForExistence(timeout: 10))
        let search = app.searchFields.firstMatch
        if !search.exists {
            let searchButton = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'search' OR title CONTAINS[c] 'search'")).firstMatch
            if searchButton.exists { activate(searchButton) }
        }
        activate(search); search.typeText("Color differs\n")
        assertDisappears(element("reviews.row.review-0", app))
        XCTAssertTrue(element("reviews.row.review-2", app).waitForExistence(timeout: 10))
        openReview("review-2", app)
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "Guest reviewer", "Guest reviewer")).firstMatch.waitForExistence(timeout: 10))
        capture("review-external-customer", app)
    }

    func testEditPublicReplyLanguageAndCustomFieldRetainsFailure() {
        let app = launch(["--review-detail", "--fail-save-once"])
        let edit = element("review.edit", app)
        XCTAssertTrue(edit.waitForExistence(timeout: 15)); wait(edit, "enabled == true")
        XCTAssertLessThan(element("review.title", app).frame.minY - element("review.status", app).frame.maxY, 40)
        capture("review-detail", app)
        #if os(iOS)
        XCUIDevice.shared.orientation = .landscapeLeft
        waitOrientation(app, landscape: true)
        capture("review-detail-landscape", app)
        XCUIDevice.shared.orientation = .portrait
        waitOrientation(app, landscape: false)
        #endif
        activate(edit)
        let reply = app.textViews["review.edit.reply"].firstMatch
        activate(reply); reply.typeText("Thank you for your detailed feedback!")
        let draft = reply.value as? String
        tap("review.edit.language", app)
        tap("entity.option.de", app); tap("entity.apply", app)
        let reference = element("customField.review_reference", app)
        reveal(reference, app); activate(reference); reference.typeText(" updated")
        tap("review.edit.save", app)
        XCTAssertTrue(element("review.saveError", app).waitForExistence(timeout: 10))
        reveal(reply, app, earlier: true)
        XCTAssertEqual(reply.value as? String, draft)
        capture("review-edit-retained", app)
        tap("review.edit.save", app)
        XCTAssertTrue(element("review.edit.save", app).waitForNonExistence(timeout: 30), app.debugDescription)
        let publicReply = element("review.reply", app)
        reveal(publicReply, app)
        XCTAssertTrue(publicReply.waitForExistence(timeout: 10), app.debugDescription)
        wait(publicReply, "label CONTAINS 'Thank you' OR value CONTAINS 'Thank you'")
        capture("review-replied", app)
    }

    func testApprovalUpdatesAndDeleteReturnsToListing() {
        let app = launch()
        openReview("review-0", app)
        tap("review.actions", app); tap("review.approve", app)
        wait(element("review.status", app), "label CONTAINS 'Approved' OR title CONTAINS 'Approved'")
        tap("review.actions", app); tap("review.approve", app)
        wait(element("review.status", app), "label CONTAINS 'Pending' OR title CONTAINS 'Pending'")
        tap("review.actions", app); tap("review.delete", app)
        capture("review-delete-confirmation", app)
        tap("Delete review", app)
        XCTAssertTrue(element("reviews.filters", app).waitForExistence(timeout: 10))
        assertDisappears(element("reviews.row.review-0", app))
        XCTAssertTrue(element("reviews.row.review-1", app).exists)
    }

    func testBulkDeleteRetainsOnlyFailedSelection() {
        let app = launch(["--fail-delete-review-1-once"])
        XCTAssertTrue(element("reviews.row.review-0", app).waitForExistence(timeout: 15))
        tap("reviews.actions", app); tap("reviews.selectLoaded", app)
        tap("reviews.deleteSelected", app); tap("Delete 3 reviews", app)
        XCTAssertTrue(element("OK", app).waitForExistence(timeout: 10))
        capture("reviews-delete-partial-failure", app)
        tap("OK", app)
        assertDisappears(element("reviews.row.review-0", app))
        XCTAssertTrue(element("reviews.row.review-1", app).exists)
        tap("reviews.deleteSelected", app); tap("Delete review", app)
        XCTAssertTrue(app.staticTexts["No reviews yet"].waitForExistence(timeout: 10))
        capture("reviews-empty", app)
    }

    func testReadOnlyGermanLargeText() {
        let app = launch(["--review-detail", "--read-only", "--large-text"], german: true)
        let edit = element("review.edit", app)
        XCTAssertTrue(edit.waitForExistence(timeout: 15))
        XCTAssertTrue(element("review.title", app).waitForExistence(timeout: 10))
        XCTAssertFalse(edit.isEnabled)
        capture("review-german-large-text", app)
        tap("review.actions", app)
        XCTAssertFalse(element("review.approve", app).exists)
        XCTAssertFalse(element("review.delete", app).exists)
    }

    func testGermanLargeTextListingUsesApprovalMenu() {
        let app = launch(["--read-only", "--large-text"], german: true)
        XCTAssertTrue(element("reviews.row.review-0", app).waitForExistence(timeout: 15))
        let approval = element("reviews.approval", app)
        XCTAssertTrue(approval.isHittable)
        capture("reviews-german-large-list", app)
        activate(approval)
        tap("Ausstehend", app)
        assertDisappears(element("reviews.row.review-1", app))
    }

    func testLoadingErrorsRetryAndPagination() {
        let app = launch(["--fail-list-once", "--many-reviews"])
        XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@ OR value CONTAINS %@", "Fixture request failed. Please retry.", "Fixture request failed. Please retry.")).firstMatch.waitForExistence(timeout: 15))
        tap("Retry", app)
        XCTAssertTrue(element("reviews.row.review-0", app).waitForExistence(timeout: 10))
        tap("reviews.loadMore", app)
        assertDisappears(element("reviews.loadMore", app))
        capture("reviews-paged", app)
    }
    #if os(iOS)
    private func waitOrientation(_ app: XCUIApplication, landscape: Bool) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let size = app.windows.firstMatch.frame.size
            return landscape ? size.width > size.height : size.height > size.width
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 8), .completed)
    }
    #endif
}
