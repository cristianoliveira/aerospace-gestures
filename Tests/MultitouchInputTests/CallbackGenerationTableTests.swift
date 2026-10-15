import XCTest

import MultitouchBridge

final class CallbackGenerationTableTests: XCTestCase {
  func testSlotsKeepTheirOriginalTokensAndAreNeverReused() {
    guard let table = AGCreateCallbackGenerationTable(2) else {
      return XCTFail("Expected a callback generation table")
    }
    defer { AGDestroyCallbackGenerationTable(table) }

    var firstSlot = 0
    var secondSlot = 0
    var exhaustedSlot = 0

    XCTAssertEqual(AGReserveCallbackGeneration(table, 101, &firstSlot), 0)
    XCTAssertEqual(AGReserveCallbackGeneration(table, 202, &secondSlot), 0)
    XCTAssertEqual(firstSlot, 0)
    XCTAssertEqual(secondSlot, 1)
    XCTAssertEqual(AGCallbackGenerationToken(table, firstSlot), 101)
    XCTAssertEqual(AGCallbackGenerationToken(table, secondSlot), 202)

    XCTAssertEqual(AGReserveCallbackGeneration(table, 303, &exhaustedSlot), -1)
    XCTAssertEqual(AGCallbackGenerationToken(table, firstSlot), 101)
    XCTAssertEqual(AGCallbackGenerationToken(table, secondSlot), 202)
    XCTAssertEqual(AGCallbackGenerationToken(table, 2), 0)
  }
}
