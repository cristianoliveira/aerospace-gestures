import GestureCore
import XCTest

@testable import GestureCLIPolicy

final class CommandDecisionTests: XCTestCase {
  func testPinchBindingsAreExplicitAndNeverSelectedInDryRun() throws {
    let configuration = try Configuration.load(
      Data(
        """
        [[bindings]]
        fingers = 2
        direction = "in"
        command = ["/bin/echo", "in"]

        [[bindings]]
        fingers = 2
        direction = "out"
        command = ["/bin/echo", "out"]

        [[bindings]]
        fingers = 3
        direction = "in"
        command = ["/bin/echo", "three-in"]

        [[bindings]]
        fingers = 4
        direction = "out"
        command = ["/bin/echo", "four-out"]

        [[bindings]]
        fingers = 5
        direction = "in"
        command = ["/bin/echo", "five-in"]

        [[bindings]]
        fingers = 3
        direction = "left"
        command = ["/bin/echo", "swipe"]
        """.utf8))

    XCTAssertNil(CommandDecision.binding(for: .pinchIn, in: configuration.bindings, dryRun: true))
    XCTAssertEqual(
      CommandDecision.binding(for: .pinchIn, in: configuration.bindings, dryRun: false)?.command,
      ["/bin/echo", "in"])
    XCTAssertEqual(
      CommandDecision.binding(for: .pinchOut, in: configuration.bindings, dryRun: false)?.command,
      ["/bin/echo", "out"])
    XCTAssertEqual(
      CommandDecision.binding(
        for: Gesture(fingers: 3, direction: .pinchIn),
        in: configuration.bindings,
        dryRun: false)?.command,
      ["/bin/echo", "three-in"])
    XCTAssertEqual(
      CommandDecision.binding(
        for: Gesture(fingers: 4, direction: .pinchOut),
        in: configuration.bindings,
        dryRun: false)?.command,
      ["/bin/echo", "four-out"])
    XCTAssertEqual(
      CommandDecision.binding(
        for: Gesture(fingers: 5, direction: .pinchIn),
        in: configuration.bindings,
        dryRun: false)?.command,
      ["/bin/echo", "five-in"])
    XCTAssertEqual(
      CommandDecision.binding(
        for: Gesture(fingers: 3, direction: .left),
        in: configuration.bindings,
        dryRun: false)?.command,
      ["/bin/echo", "swipe"])
    XCTAssertNil(
      CommandDecision.binding(
        for: Gesture(fingers: 4, direction: .pinchIn),
        in: configuration.bindings,
        dryRun: false))
  }

  func testSelectsMatchingBindingOnlyWhenExecutionIsEnabled() throws {
    let configuration = try Configuration.load(
      Data(
        """
        [[bindings]]
        fingers = 3
        direction = "left"
        command = ["/bin/echo"]
        """.utf8))
    let gesture = Gesture(fingers: 3, direction: .left)

    XCTAssertNil(CommandDecision.binding(for: gesture, in: configuration.bindings, dryRun: true))
    XCTAssertEqual(
      CommandDecision.binding(for: gesture, in: configuration.bindings, dryRun: false)?.command,
      ["/bin/echo"])
    XCTAssertNil(
      CommandDecision.binding(
        for: Gesture(fingers: 4, direction: .left), in: configuration.bindings, dryRun: false))
  }
}
