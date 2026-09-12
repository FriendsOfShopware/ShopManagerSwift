import XCTest

@MainActor
func replaceText(_ field: XCUIElement, with value: String, numeric: Bool = false, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(field.waitForExistence(timeout: 10), field.debugDescription, file: file, line: line)
    #if os(iOS)
    let app = XCUIApplication()
    let current = field.value as? String ?? ""
    if !current.isEmpty && current != field.placeholderValue {
        if numeric {
            // Select before iPad's floating numeric keypad covers the field.
            field.tap(withNumberOfTaps: 3, numberOfTouches: 1)
        } else {
            // The full keyboard can move an iPad sheet on focus. Open the menu
            // only after that move, so selection uses the field's new position.
            field.tap()
            let selectAll = app.menuItems["Select All"]
            // Tapping an already-focused field may open the menu itself.
            if !selectAll.waitForExistence(timeout: 1) { field.press(forDuration: 1.1) }
            XCTAssertTrue(selectAll.waitForExistence(timeout: 3), app.debugDescription, file: file, line: line)
            selectAll.tap()
        }
        app.typeText(XCUIKeyboardKey.delete.rawValue)
    } else {
        field.tap()
    }
    XCTAssertTrue((field.value as? String) == "" || (field.value as? String) == field.placeholderValue,
                  "Could not clear \(field.identifier): \(field.debugDescription)", file: file, line: line)
    if !value.isEmpty { app.typeText(value) }
    #else
    field.click()
    field.typeKey("a", modifierFlags: .command)
    field.typeText(value.isEmpty ? XCUIKeyboardKey.delete.rawValue : value)
    #endif
    if value.isEmpty {
        // UIKit can expose the placeholder as an empty field's AX value.
        XCTAssertTrue((field.value as? String) == "" || (field.value as? String) == field.placeholderValue,
                      field.debugDescription, file: file, line: line)
    } else {
        XCTAssertEqual(field.value as? String, value, file: file, line: line)
    }
}
