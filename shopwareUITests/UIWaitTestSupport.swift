import XCTest

@MainActor
func assertDisappears(_ element: XCUIElement, timeout: TimeInterval = 30, file: StaticString = #filePath, line: UInt = #line) {
    // Native disappearance waits avoid nested existence retries inside a
    // predicate poll when accessibility snapshots are slow on hosted runners.
    XCTAssertTrue(element.waitForNonExistence(timeout: timeout), element.debugDescription, file: file, line: line)
}
