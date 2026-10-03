import GestureCore
import XCTest

@testable import GestureCLIPolicy

final class CommandDecisionTests: XCTestCase {
  func testPinchBindingsAreExplicitAndNeverSelectedInDryRun() throws {
    let configuration = try Configuration.load(
      Data(
        """
        [[bindings]]
        gesture = "pinch_in"
        command = ["/bin/echo", "in"]

        [[bindings]]
        gesture = "pinch_out"
        command = ["/bin/echo", "out"]
        """.utf8))

    XCTAssertNil(CommandDecision.binding(for: .pinchIn, in: configuration.bindings, dryRun: true))
    XCTAssertEqual(
      CommandDecision.binding(for: .pinchIn, in: configuration.bindings, dryRun: false)?.command,
      ["/bin/echo", "in"])
    XCTAssertEqual(
      CommandDecision.binding(for: .pinchOut, in: configuration.bindings, dryRun: false)?.command,
      ["/bin/echo", "out"])
    XCTAssertNil(
      CommandDecision.binding(
        for: Gesture(fingers: 3, direction: .left), in: configuration.bindings, dryRun: false))
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
