import XCTest

@MainActor
final class MediaUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        #if os(iOS)
        XCUIDevice.shared.orientation = .portrait
        #endif
    }

    private func launch(_ arguments: [String] = [], german: Bool = false, waitForFiles: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--media-ui-fixtures", "-AppleLanguages", german ? "(de)" : "(en)",
                               "-AppleLocale", german ? "de_DE" : "en_US", "-ApplePersistenceIgnoreState", "YES"] + arguments
        app.launch()
        #if os(macOS)
        if !app.windows.firstMatch.waitForExistence(timeout: 3) {
            app.menuBarItems[german ? "Ablage" : "File"].click()
            app.menuItems[german ? "Neues Fenster" : "New Window"].click()
        }
        #endif
        if waitForFiles { XCTAssertTrue(app.buttons["media.file.image-1"].waitForExistence(timeout: 15), app.debugDescription) }
        return app
    }

    private func activate(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 8), element.debugDescription)
        #if os(macOS)
        element.click()
        #else
        element.tap()
        #endif
    }

    private func control(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        #if os(macOS)
        for query in [app.windows.firstMatch.buttons, app.menuButtons, app.popUpButtons, app.menuItems] {
            let element = query[id].firstMatch
            if element.exists && element.isHittable { return element }
        }
        #endif
        return app.buttons[id].firstMatch
    }
    private func tap(_ id: String, _ app: XCUIApplication) { activate(control(id, app)) }
    private func wait(_ element: XCUIElement, _ predicate: String) {
        XCTAssertEqual(XCTWaiter.wait(for: [XCTNSPredicateExpectation(predicate: NSPredicate(format: predicate), object: element)], timeout: 10), .completed, element.debugDescription)
    }
    private func capture(_ name: String) {
        #if os(macOS)
        let screenshot = XCTAttachment(screenshot: XCUIApplication().windows.firstMatch.screenshot())
        #else
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        #endif
        screenshot.name = name; screenshot.lifetime = .keepAlways; add(screenshot)
    }
    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<6 {
            if element.exists && element.isHittable { return }
            let scroll = app.scrollViews["media.inspector.content"]
            #if os(macOS)
            scroll.scroll(byDeltaX: 0, deltaY: -220)
            #else
            scroll.swipeUp()
            #endif
        }
        XCTAssertTrue(element.isHittable, app.debugDescription)
    }

    func testBrowseFoldersListAndInspector() {
        let app = launch()
        let breadcrumbsY = app.buttons["media.root"].frame.midY
        let footerY = app.staticTexts["media.fileCount"].frame.midY
        capture("media-grid")
        tap("media.folder.products", app)
        XCTAssertTrue(app.buttons["media.folder.summer"].waitForExistence(timeout: 8))
        tap("media.folder.summer", app)
        XCTAssertTrue(app.staticTexts["This folder is empty"].waitForExistence(timeout: 8))
        capture("media-empty-folder")
        XCTAssertEqual(app.buttons["media.root"].frame.midY, breadcrumbsY, accuracy: 2,
                       "Entering an empty folder must keep the breadcrumbs at the top.")
        XCTAssertEqual(app.staticTexts["media.fileCount"].frame.midY, footerY, accuracy: 2,
                       "Entering an empty folder must keep the footer at the bottom.")
        tap("media.root", app)
        XCTAssertTrue(app.buttons["media.file.image-1"].waitForExistence(timeout: 8))
        tap("media.options", app)
        if !control("List", app).exists { tap("View", app) }
        tap("List", app)
        XCTAssertTrue(app.descendants(matching: .any)["media.list"].firstMatch.waitForExistence(timeout: 8), app.debugDescription)
        capture("media-list")
        tap("media.file.image-1", app)
        XCTAssertTrue(app.buttons["media.inspector.close"].waitForExistence(timeout: 8))
        capture("media-inspector")
        reveal(app.buttons["media.edit"], app)
        XCTAssertTrue(app.buttons["media.edit"].isEnabled)
        #if os(iOS)
        XCUIDevice.shared.orientation = .landscapeLeft
        waitForOrientation(app, landscape: true)
        XCTAssertTrue(app.buttons["media.inspector.close"].waitForExistence(timeout: 8))
        capture("media-inspector-landscape")
        XCUIDevice.shared.orientation = .portrait
        waitForOrientation(app, landscape: false)
        XCTAssertTrue(app.buttons["media.inspector.close"].waitForExistence(timeout: 8))
        XCTAssertTrue(app.staticTexts["File details"].exists)
        capture("media-inspector-portrait-restored")
        #endif
        tap("media.inspector.close", app)
        wait(app.buttons["media.inspector.close"], "exists == false")
    }

    #if os(iOS)
    private func waitForOrientation(_ app: XCUIApplication, landscape: Bool) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            let frame = app.windows.firstMatch.frame
            return landscape ? frame.width > frame.height : frame.height > frame.width
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 8), .completed)
    }
    #endif

    func testEditRetryAndMove() {
        let app = launch(["--fail-save-once"])
        tap("media.file.image-1", app)
        reveal(app.buttons["media.edit"], app)
        tap("media.edit", app)
        let title = app.textFields["media.title"]
        activate(title)
        title.typeText(" updated")
        let draft = title.value as? String
        tap("media.details.save", app)
        XCTAssertTrue(app.staticTexts["Fixture request failed. Please retry."].firstMatch.waitForExistence(timeout: 8))
        XCTAssertEqual(title.value as? String, draft)
        capture("media-edit-retains-draft")
        tap("media.details.save", app)
        wait(app.buttons["media.details.save"], "exists == false")
        reveal(app.buttons["media.inspector.move"], app)
        tap("media.inspector.move", app)
        tap("media.move.folder.products", app)
        wait(app.buttons["media.move.confirm"], "enabled == true")
        capture("media-move-destination")
        tap("media.move.confirm", app)
        wait(app.buttons["media.inspector.close"], "exists == false")
        wait(app.buttons["media.file.image-1"], "exists == false")
        tap("media.folder.products", app)
        XCTAssertTrue(app.buttons["media.file.image-1"].waitForExistence(timeout: 8))
        capture("media-moved-file")
    }

    func testPartialDeleteKeepsFailedFileSelected() {
        let app = launch(["--fail-delete-once"])
        tap("media.options", app); tap("media.select", app)
        tap("media.file.image-1", app); tap("media.file.image-2", app)
        XCTAssertTrue(app.staticTexts["2 selected"].exists)
        tap("media.delete", app); tap("media.delete.confirm", app)
        XCTAssertTrue(app.staticTexts["1 selected"].waitForExistence(timeout: 8), app.debugDescription)
        XCTAssertFalse(app.buttons["media.file.image-1"].exists)
        XCTAssertTrue(app.buttons["media.file.image-2"].exists)
        capture("media-partial-delete")
        tap("media.delete", app); tap("media.delete.confirm", app)
        wait(app.buttons["media.file.image-2"], "exists == false")
    }

    func testGermanLargeTextAndReadOnly() {
        let app = launch(["--read-only", "--large-text"], german: true)
        XCTAssertTrue(app.buttons["media.root"].exists)
        XCTAssertFalse(control("media.upload", app).isEnabled)
        capture("media-german-large-text")
        tap("media.file.image-1", app)
        XCTAssertTrue(app.staticTexts["Dateidetails"].waitForExistence(timeout: 8))
        reveal(app.buttons["media.edit"], app)
        XCTAssertFalse(app.buttons["media.edit"].isEnabled)
        capture("media-inspector-german-large-text")
    }

    func testListFailureCanBeRetried() {
        let app = launch(["--fail-list-once"], waitForFiles: false)
        XCTAssertTrue(app.staticTexts["Couldn't load media"].waitForExistence(timeout: 8))
        tap("Retry", app)
        XCTAssertTrue(app.buttons["media.file.image-1"].waitForExistence(timeout: 8))
    }

    func testCreateFolderAndSearch() {
        let app = launch()
        tap("media.options", app); tap("New folder…", app)
        activate(app.textFields["media.folderName"])
        app.textFields["media.folderName"].typeText("Launch assets")
        tap("media.folder.save", app)
        wait(app.buttons["media.folder.save"], "exists == false")
        #if os(macOS)
        // macOS combines the folder name and subfolder count into the button's label.
        activate(app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@ AND label BEGINSWITH %@",
                                                  "media.folder.", "Launch assets")).firstMatch)
        #else
        activate(app.staticTexts["Launch assets"].firstMatch)
        #endif
        XCTAssertTrue(app.staticTexts["This folder is empty"].waitForExistence(timeout: 8))
        tap("media.root", app)
        activate(app.searchFields.firstMatch)
        app.searchFields.firstMatch.typeText("linen")
        wait(app.buttons["media.file.image-2"], "exists == false")
        XCTAssertTrue(app.buttons["media.file.image-1"].exists)
        capture("media-search")
    }
}
