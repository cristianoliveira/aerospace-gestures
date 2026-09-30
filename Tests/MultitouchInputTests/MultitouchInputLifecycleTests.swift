import GestureCore
import XCTest

@testable import MultitouchInput

final class MultitouchInputLifecycleTests: XCTestCase {
  func testRepeatedStartKeepsOriginalHandlerAndDoesNotRestartBridge() throws {
    var startCount = 0
    let input = MultitouchInputController(
      startBridge: {
        startCount += 1
        return nil
      },
      stopBridge: {})
    var firstHandlerCalls = 0
    var secondHandlerCalls = 0

    XCTAssertNil(input.start { _, _ in firstHandlerCalls += 1 })
    XCTAssertEqual(
      input.start { _, _ in secondHandlerCalls += 1 }, "Multitouch listener already started")
    input.receive(device: 1, contacts: [])

    XCTAssertEqual(startCount, 1)
    XCTAssertEqual(firstHandlerCalls, 1)
    XCTAssertEqual(secondHandlerCalls, 0)
  }

  func testFailedStartClearsHandlerAndStopDetachesTheActiveHandler() throws {
    var startCount = 0
    var stopCount = 0
    let input = MultitouchInputController(
      startBridge: {
        startCount += 1
        return startCount == 1 ? "Private API unavailable" : nil
      },
      stopBridge: { stopCount += 1 })
    var failedHandlerCalls = 0
    var activeHandlerCalls = 0

    XCTAssertEqual(input.start { _, _ in failedHandlerCalls += 1 }, "Private API unavailable")
    input.receive(device: 1, contacts: [])
    XCTAssertNil(input.start { _, _ in activeHandlerCalls += 1 })
    input.receive(device: 1, contacts: [])
    input.stop()
    input.receive(device: 1, contacts: [])

    XCTAssertEqual(startCount, 2)
    XCTAssertEqual(stopCount, 1)
    XCTAssertEqual(failedHandlerCalls, 0)
    XCTAssertEqual(activeHandlerCalls, 1)
  }
}
