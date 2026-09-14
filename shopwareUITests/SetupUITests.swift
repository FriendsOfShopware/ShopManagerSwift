import XCTest

@MainActor
final class SetupUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        #if os(iOS)
        XCUIDevice.shared.orientation = .portrait
        #endif
    }

    func testConnectPersonalizeAndCancelAdditionalShop() {
        let app = launch()
        capture("Setup – your shop", app)
        enterShop(app)
        capture("Setup – sign in", app)
        signIn(app)
        let name = app.textFields["setup.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        dismissPasswordSuggestion()
        reveal(name, app)
        replaceText(name, with: "Meadow & Moss")
        name.typeText("\n")
        activate(element("setup.tint.2", app))
        XCTAssertEqual(textValue(element("setup.preview.name", app)), "Meadow & Moss")
        capture("Setup – make it yours", app)
        activate(element("setup.continue", app))
        let completed = element("setup.completed", app)
        XCTAssertTrue(completed.waitForExistence(timeout: 10))
        XCTAssertEqual(textValue(completed), "Meadow & Moss")
        activate(element("setup.addShop", app))
        XCTAssertTrue(app.textFields["setup.address"].waitForExistence(timeout: 10))
        capture("Setup – additional shop", app)
        activate(element("setup.cancel", app))
        XCTAssertTrue(completed.waitForExistence(timeout: 10))
        XCTAssertFalse(app.textFields["setup.address"].exists)
    }

    func testConnectionAndSignInFailuresRetainInput() {
        let app = launch(["--setup-fail-url-once", "--setup-fail-login-once"])
        replaceText(app.textFields["setup.address"], with: "not a shop")
        activate(element("setup.continue", app))
        XCTAssertTrue(element("setup.error", app).waitForExistence(timeout: 5))
        replaceText(app.textFields["setup.address"], with: "setup-ui.test/admin")
        activate(element("setup.continue", app))
        XCTAssertTrue(element("setup.error", app).waitForExistence(timeout: 5))
        XCTAssertEqual(app.textFields["setup.address"].value as? String, "setup-ui.test/admin")
        activate(element("setup.continue", app))
        signIn(app)
        XCTAssertTrue(element("setup.error", app).waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields["setup.username"].value as? String, "admin")
        activate(element("setup.passwordVisibility", app))
        XCTAssertEqual(app.textFields["setup.password"].value as? String, "fixture-password")
        capture("Setup – sign-in retry", app)
        activate(element("setup.continue", app))
        XCTAssertTrue(app.textFields["setup.name"].waitForExistence(timeout: 10))
        activate(element("setup.back", app))
        XCTAssertTrue(app.secureTextFields["setup.password"].waitForExistence(timeout: 10))
        XCTAssertEqual(app.textFields["setup.username"].value as? String, "admin")
        activate(element("setup.back", app))
        XCTAssertEqual(app.textFields["setup.address"].value as? String, "setup-ui.test/admin")
    }

    func testGermanLargeTextDarkSetup() {
        let app = launch(["--large-text", "--dark"], german: true)
        XCTAssertEqual(textValue(element("setup.heading", app)), "Shop verbinden")
        XCTAssertTrue(element("setup.continue", app).isHittable)
        capture("Setup – German large text dark", app)
        reveal(app.textFields["setup.address"], app)
        enterShop(app)
        signIn(app)
        let name = app.textFields["setup.name"]
        XCTAssertTrue(name.waitForExistence(timeout: 10))
        dismissPasswordSuggestion()
        reveal(name, app)
        capture("Setup – German personalization", app)
        XCTAssertTrue(element("setup.continue", app).isHittable)
        XCTAssertEqual(element("setup.continue", app).label, "Shop öffnen")
        activate(element("setup.continue", app))
        XCTAssertTrue(element("setup.completed", app).waitForExistence(timeout: 10))
    }

    private func launch(_ args: [String] = [], german: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--setup-ui-fixtures", "-AppleLanguages", german ? "(de)" : "(en)", "-AppleLocale", german ? "de_DE" : "en_US"] + args
        app.launch()
        XCTAssertTrue(app.textFields["setup.address"].waitForExistence(timeout: 15))
        return app
    }

    private func enterShop(_ app: XCUIApplication) {
        replaceText(app.textFields["setup.address"], with: "setup-ui.test/admin")
        activate(element("setup.continue", app))
        XCTAssertTrue(app.textFields["setup.username"].waitForExistence(timeout: 10))
    }

    private func dismissPasswordSuggestion() {
        #if os(iOS)
        // Password AutoFill presents its own remote view after a successful sign-in.
        // Keep the native feature enabled and decline saving only fixture credentials.
        let appButton = XCUIApplication().buttons["Not Now"]
        if appButton.waitForExistence(timeout: 2) {
            appButton.tap()
            return
        }
        let service = XCUIApplication(bundleIdentifier: "com.apple.SafariViewService")
        let notNow = service.buttons["Not Now"]
        if notNow.waitForExistence(timeout: 3) {
            let app = XCUIApplication()
            // Give XCTest's native alert handler a harmless app interaction to intercept.
            // Activating the remote service itself can dismiss the alert and leave a stale button.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.05)).tap()
            if notNow.exists {
                let frame = notNow.frame, origin = app.frame.origin
                app.coordinate(withNormalizedOffset: .zero)
                    .withOffset(CGVector(dx: frame.midX - origin.x, dy: frame.midY - origin.y)).tap()
            }
        }
        #endif
    }

    private func signIn(_ app: XCUIApplication) {
        replaceText(app.textFields["setup.username"], with: "admin")
        let password = app.secureTextFields["setup.password"]
        reveal(password, app)
        activate(password)
        password.typeText("fixture-password")
        activate(element("setup.continue", app))
    }

    private func element(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        #if os(macOS)
        app.windows.descendants(matching: .any).matching(identifier: id).firstMatch
        #else
        app.descendants(matching: .any).matching(identifier: id).firstMatch
        #endif
    }

    private func textValue(_ element: XCUIElement) -> String {
        element.label.isEmpty ? (element.value as? String ?? "") : element.label
    }

    private func activate(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), element.debugDescription)
        #if os(macOS)
        element.click()
        #else
        element.tap()
        #endif
    }

    private func reveal(_ element: XCUIElement, _ app: XCUIApplication) {
        for _ in 0..<5 {
            if element.isHittable { return }
            #if os(macOS)
            app.scrollViews.firstMatch.scroll(byDeltaX: 0, deltaY: -180)
            #else
            app.scrollViews.firstMatch.swipeUp()
            #endif
        }
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        #if os(macOS)
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        #else
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        #endif
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
