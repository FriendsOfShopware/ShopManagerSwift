import XCTest

@MainActor
func replaceText(_ field: XCUIElement, with value: String, numeric: Bool = false, file: StaticString = #filePath, line: UInt = #line) {
    XCTAssertTrue(field.waitForExistence(timeout: 10), field.debugDescription, file: file, line: line)
    #if os(iOS)
    let app = XCUIApplication()
    let current = field.value as? String ?? ""
    if !current.isEmpty && current != field.placeholderValue {
        // Start at the text's trailing edge before iPad can move the sheet.
        // Backspace works for both text and numeric keyboards without relying
        // on edit-menu placement or an attached hardware keyboard.
        field.coordinate(withNormalizedOffset: CGVector(dx: 1, dy: 0.5))
            .withOffset(CGVector(dx: -1, dy: 0)).tap()
        app.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count))
    } else {
        field.tap()
    }
    XCTAssertTrue((field.value as? String) == "" || (field.value as? String) == field.placeholderValue,
                  "Could not clear \(field.identifier): \(field.debugDescription)", file: file, line: line)
    if numeric {
        // Linked price fields redraw their companion value on each keystroke.
        // Wait for that update before sending the next key; fast batched typing
        // on iOS 26 can otherwise drop input while the keyboard/layout changes.
        var entered = ""
        for character in value {
            entered.append(character)
            app.typeText(String(character))
            let updated = XCTNSPredicateExpectation(predicate: NSPredicate(format: "value == %@", entered), object: field)
            XCTAssertEqual(XCTWaiter.wait(for: [updated], timeout: 5), .completed,
                           field.debugDescription, file: file, line: line)
        }
    } else if !value.isEmpty {
        app.typeText(value)
    }
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
