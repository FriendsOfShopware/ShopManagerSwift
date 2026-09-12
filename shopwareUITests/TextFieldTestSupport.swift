import XCTest

@MainActor
func replaceText(_ field: XCUIElement, with value: String, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(field.waitForExistence(timeout: 10), field.debugDescription, file: file, line: line)
    #if os(iOS)
    let app = XCUIApplication()
    let current = field.value as? String ?? ""
    if !current.isEmpty && current != field.placeholderValue {
        // Select the single-line value as the initial focus gesture. A second
        // gesture or Cmd-A after iPad opens its floating keypad can miss the field.
        field.tap(withNumberOfTaps: 3, numberOfTouches: 1)
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
