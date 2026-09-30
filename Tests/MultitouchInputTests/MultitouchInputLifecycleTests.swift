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

    XCTAssertNil(input.start { _, _, _ in firstHandlerCalls += 1 })
    XCTAssertEqual(
      input.start { _, _, _ in secondHandlerCalls += 1 }, "Multitouch listener already started")
    input.receive(device: 1, frame: 1, contacts: [])

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

    XCTAssertEqual(input.start { _, _, _ in failedHandlerCalls += 1 }, "Private API unavailable")
    input.receive(device: 1, frame: 1, contacts: [])
    XCTAssertNil(input.start { _, _, _ in activeHandlerCalls += 1 })
    input.receive(device: 1, frame: 1, contacts: [])
    input.stop()
    input.receive(device: 1, frame: 2, contacts: [])

    XCTAssertEqual(startCount, 2)
    XCTAssertEqual(stopCount, 1)
    XCTAssertEqual(failedHandlerCalls, 0)
    XCTAssertEqual(activeHandlerCalls, 1)
  }

  func testOutOfOrderFramesCannotReachHandlerAfterNewerLiftFrame() throws {
    let input = MultitouchInputController(startBridge: { nil }, stopBridge: {})
    var deliveredFrames: [UInt32] = []
    var deliveredContactCounts: [Int] = []
    XCTAssertNil(
      input.start { _, frame, contacts in
        deliveredFrames.append(frame)
        deliveredContactCounts.append(contacts.count)
      })

    input.receive(device: 1, frame: 10, contacts: [Contact(id: 1, x: 0.5, y: 0.5)])
    input.receive(device: 1, frame: 12, contacts: [])
    input.receive(device: 1, frame: 11, contacts: [Contact(id: 1, x: 0.4, y: 0.5)])
    input.receive(device: 1, frame: 13, contacts: [Contact(id: 1, x: 0.3, y: 0.5)])

    XCTAssertEqual(deliveredFrames, [10, 12, 13])
    XCTAssertEqual(deliveredContactCounts, [1, 0, 1])
  }

  func testConcurrentCallbacksReachHandlerInMonotonicSequenceOrder() {
    let input = MultitouchInputController(startBridge: { nil }, stopBridge: {})
    var deliveredFrames: [UInt32] = []
    XCTAssertNil(input.start { _, frame, _ in deliveredFrames.append(frame) })

    DispatchQueue.concurrentPerform(iterations: 100) { index in
      input.receive(device: 1, frame: UInt32(index + 1), contacts: [])
    }

    XCTAssertFalse(deliveredFrames.isEmpty)
    XCTAssertEqual(deliveredFrames, deliveredFrames.sorted())
    XCTAssertEqual(deliveredFrames.count, Set(deliveredFrames).count)
  }

  func testFrameSequenceOrderingHandlesWraparound() throws {
    let input = MultitouchInputController(startBridge: { nil }, stopBridge: {})
    var deliveredFrames: [UInt32] = []
    XCTAssertNil(input.start { _, frame, _ in deliveredFrames.append(frame) })

    input.receive(device: 1, frame: UInt32.max, contacts: [])
    input.receive(device: 1, frame: 0, contacts: [])
    input.receive(device: 1, frame: UInt32.max, contacts: [])

    XCTAssertEqual(deliveredFrames, [UInt32.max, 0])
  }
}
