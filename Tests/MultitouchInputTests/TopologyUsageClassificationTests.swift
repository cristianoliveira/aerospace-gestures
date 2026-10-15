import MultitouchBridge
import XCTest

final class TopologyUsageClassificationTests: XCTestCase {
  func testClassifiesTouchPadMatchNonmatchAndInvalidUsagePairs() {
    XCTAssertEqual(AGClassifyHIDUsagePairs(1, 1, 0), 1)
    XCTAssertEqual(AGClassifyHIDUsagePairs(1, 0, 0), 0)
    XCTAssertEqual(AGClassifyHIDUsagePairs(0, 0, 0), -1)
    XCTAssertEqual(AGClassifyHIDUsagePairs(1, 0, 1), -1)

    // A usable TouchPad entry wins even if another entry is malformed.
    XCTAssertEqual(AGClassifyHIDUsagePairs(1, 1, 1), 1)
  }
}
