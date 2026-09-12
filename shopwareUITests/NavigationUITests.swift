import XCTest

@MainActor
final class NavigationUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        #if os(iOS)
        XCUIDevice.shared.orientation = .portrait
        #endif
    }

    private var isPhone: Bool {
        #if os(iOS)
        UIDevice.current.userInterfaceIdiom == .phone
        #else
        false
        #endif
    }

    private func launch(_ arguments: [String] = [], german: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--navigation-ui-fixtures", "-AppleLanguages", german ? "(de)" : "(en)",
                               "-AppleLocale", german ? "de_DE" : "en_US",
                               "-ApplePersistenceIgnoreState", "YES"] + arguments
        app.launch()
        #if os(macOS)
        if !app.windows.firstMatch.waitForExistence(timeout: 3) {
            app.menuBarItems[german ? "Ablage" : "File"].click()
            app.menuItems[german ? "Neues Fenster" : "New Window"].click()
        }
        #endif
        if arguments.contains("--navigation-deep-link") {
            XCTAssertTrue(app.buttons["order.edit"].waitForExistence(timeout: 15), app.debugDescription)
        } else {
            XCTAssertTrue(element("navigation.shopSwitcher", app).waitForExistence(timeout: 15), app.debugDescription)
        }
        return app
    }

    private func element(_ id: String, _ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    private func tap(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), element.debugDescription)
        #if os(macOS)
        element.click()
        #else
        element.tap()
        #endif
    }

    private func destination(_ id: String, _ title: String, _ app: XCUIApplication) {
        if isPhone { tap(app.tabBars.buttons[title]) }
        else { tap(element("navigation.destination." + id, app)) }
    }

    private func capture(_ name: String, _ app: XCUIApplication) {
        #if os(macOS)
        let attachment = XCTAttachment(screenshot: app.windows.firstMatch.screenshot())
        #else
        let attachment = XCTAttachment(screenshot: app.screenshot())
        #endif
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func openOrder(_ app: XCUIApplication) {
        destination("orders", "Orders", app)
        XCTAssertTrue(app.staticTexts["#10001"].firstMatch.waitForExistence(timeout: 15), app.debugDescription)
        #if os(macOS)
        app.staticTexts["#10001"].firstMatch.doubleClick()
        #else
        tap(element("orders.row.order-0", app))
        #endif
        XCTAssertTrue(app.buttons["order.edit"].waitForExistence(timeout: 10))
    }

    func testDestinationsAndCatalog() {
        let app = launch()
        if isPhone {
            XCTAssertEqual(app.tabBars.buttons.count, 5)
            XCTAssertFalse(app.tabBars.buttons["More"].exists)
            XCTAssertTrue(app.tabBars.buttons["Catalog"].isHittable)
        } else {
            XCTAssertFalse(app.tabBars.firstMatch.exists)
            let home = element("navigation.destination.home", app)
            XCTAssertLessThan(home.frame.midY, app.windows.firstMatch.frame.minY + app.windows.firstMatch.frame.height * 0.25)
            XCTAssertTrue(element("navigation.destination.media", app).isHittable)
        }
        capture("navigation-home", app)
        destination("orders", "Orders", app)
        XCTAssertTrue(app.staticTexts["#10001"].firstMatch.waitForExistence(timeout: 15))
        capture("navigation-orders", app)
        if isPhone {
            app.swipeUp()
            XCTAssertTrue(app.tabBars.buttons["Catalog"].isHittable)
            destination("catalog", "Catalog", app)
            for id in ["products", "promotions", "media", "reviews"] {
                XCTAssertTrue(element("navigation.destination." + id, app).isHittable)
            }
            capture("navigation-catalog", app)
        }
        tap(element("navigation.destination.media", app))
        XCTAssertTrue(element("media.file.image-1", app).waitForExistence(timeout: 15), app.debugDescription)
        capture("navigation-media", app)
        if isPhone {
            destination("home", "Home", app)
            destination("catalog", "Catalog", app)
            XCTAssertTrue(element("media.file.image-1", app).waitForExistence(timeout: 10))
        }
    }

    func testDetailSurvivesTabSwitchAndWindowAdaptation() {
        let app = launch(["--resize-navigation"])
        openOrder(app)
        if isPhone {
            destination("customers", "Customers", app)
            XCTAssertTrue(app.searchFields.firstMatch.waitForExistence(timeout: 10))
            destination("orders", "Orders", app)
            XCTAssertTrue(app.buttons["order.edit"].waitForExistence(timeout: 10), app.debugDescription)
        }
        capture("navigation-order-detail", app)
        #if os(iOS)
        if !isPhone {
            tap(element("navigation.fixture.resize", app))
            XCTAssertTrue(app.buttons["order.edit"].waitForExistence(timeout: 10))
            XCTAssertFalse(element("navigation.destination.home", app).isHittable)
            capture("navigation-ipad-compact", app)
            tap(element("navigation.fixture.resize", app))
            XCTAssertTrue(element("navigation.destination.home", app).waitForExistence(timeout: 10))
        }
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["order.edit"].waitForExistence(timeout: 10))
        capture("navigation-landscape", app)
        XCUIDevice.shared.orientation = .portrait
        #endif
    }

    func testShopSwitchClearsOldDetailsAndUpdatesPermissions() {
        let app = launch()
        openOrder(app)
        if isPhone { destination("home", "Home", app) }
        tap(element("navigation.shopSwitcher", app))
        tap(element("navigation.shop.limited", app))
        let switched = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label CONTAINS %@ OR title CONTAINS %@", "Customer service", "Customer service"),
                                                 object: element("navigation.shopSwitcher", app))
        XCTAssertEqual(XCTWaiter.wait(for: [switched], timeout: 10), .completed)
        if isPhone {
            XCTAssertFalse(app.tabBars.buttons["Orders"].exists)
            XCTAssertFalse(app.tabBars.buttons["Catalog"].exists)
            XCTAssertTrue(app.tabBars.buttons["Customers"].isHittable)
        } else {
            XCTAssertFalse(element("navigation.destination.orders", app).exists)
            XCTAssertFalse(element("navigation.destination.media", app).exists)
        }
        capture("navigation-limited-shop", app)
        tap(element("navigation.shopSwitcher", app))
        tap(element("navigation.shop.storefront", app))
        destination("orders", "Orders", app)
        XCTAssertTrue(app.staticTexts["#10001"].firstMatch.waitForExistence(timeout: 15))
        XCTAssertFalse(app.buttons["order.edit"].exists)
        tap(element("navigation.shopSwitcher", app))
        tap(element("navigation.manageShops", app))
        tap(app.buttons["Done"].firstMatch)
        XCTAssertTrue(app.staticTexts["#10001"].firstMatch.waitForExistence(timeout: 10))
    }

    func testNotificationOpensOrderInTargetShop() {
        let app = launch(["--navigation-deep-link"])
        XCTAssertTrue(app.buttons["order.edit"].waitForExistence(timeout: 15), app.debugDescription)
        capture("navigation-deep-link", app)
        if isPhone {
            tap(app.navigationBars.buttons.element(boundBy: 0))
        }
        let shopSwitcher = element("navigation.shopSwitcher", app)
        // AppKit menu buttons expose their name as title; UIKit exposes it as label.
        XCTAssertTrue(shopSwitcher.label.contains("Outlet") || shopSwitcher.title.contains("Outlet"), app.debugDescription)
    }

    func testGermanLargeTextNavigation() {
        let app = launch(["--large-text"], german: true)
        capture("navigation-german-large", app)
        if isPhone {
            tap(app.tabBars.buttons["Katalog"])
            XCTAssertTrue(element("navigation.destination.products", app).isHittable)
            capture("navigation-catalog-german-large", app)
        } else {
            XCTAssertTrue(element("navigation.destination.customers", app).isHittable)
        }
    }
}
