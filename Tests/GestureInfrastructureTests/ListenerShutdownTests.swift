import XCTest

@testable import GestureInfrastructure

final class ListenerShutdownTests: XCTestCase {
  func testStopsInputBeforeCommandsAndWaitsForCommandCompletion() {
    var events: [String] = []
    var finishCommands: (() -> Void)?
    let shutdown = ListenerShutdown(
      stopInput: { events.append("input stopped") },
      stopCommands: { completion in
        events.append("commands stopping")
        finishCommands = completion
      })

    shutdown.stop { events.append("shutdown complete") }

    XCTAssertEqual(events, ["input stopped", "commands stopping"])
    finishCommands?()
    XCTAssertEqual(events, ["input stopped", "commands stopping", "shutdown complete"])
  }

  func testRepeatedSignalDoesNotRepeatStopsOrCompletion() {
    var inputStopCount = 0
    var commandStopCount = 0
    var completionCount = 0
    var finishCommands: (() -> Void)?
    let shutdown = ListenerShutdown(
      stopInput: { inputStopCount += 1 },
      stopCommands: { completion in
        commandStopCount += 1
        finishCommands = completion
      })

    shutdown.stop { completionCount += 1 }
    shutdown.stop { XCTFail("A repeated signal must not add another completion") }
    finishCommands?()
    finishCommands?()

    XCTAssertEqual(inputStopCount, 1)
    XCTAssertEqual(commandStopCount, 1)
    XCTAssertEqual(completionCount, 1)
  }
}
