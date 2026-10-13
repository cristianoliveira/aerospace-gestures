import GestureCore
import XCTest

@testable import GestureCLIPolicy

final class CommandDecisionTests: XCTestCase {
  func testMatchesSwipeAndPinchBindingsWithExactModifierSets() throws {
    let configuration = try Configuration.load(
      Data(
        """
        [[bindings]]
        fingers = 3
        direction = "left"
        command = ["/bin/echo", "plain"]

        [[bindings]]
        fingers = 3
        direction = "left"
        modifiers = ["command"]
        command = ["/bin/echo", "command"]

        [[bindings]]
        fingers = 3
        direction = "left"
        modifiers = ["shift", "command"]
        command = ["/bin/echo", "combination"]

        [[bindings]]
        fingers = 2
        direction = "in"
        modifiers = ["option", "control"]
        command = ["/bin/echo", "pinch"]
        """.utf8))
    let swipe = Gesture(fingers: 3, direction: .left)

    XCTAssertEqual(
      CommandDecision.binding(
        for: swipe, in: configuration.bindings, modifiers: .known(.none), dryRun: false)?.command,
      ["/bin/echo", "plain"])
    let commandSample =
      StubModifierStateSampler(result: .known(ModifierSet([.command]))).sample()
    XCTAssertEqual(
      CommandDecision.binding(
        for: swipe, in: configuration.bindings, modifiers: commandSample, dryRun: false)?.command,
      ["/bin/echo", "command"])
    XCTAssertEqual(
      CommandDecision.binding(
        for: swipe, in: configuration.bindings,
        modifiers: .known(ModifierSet([.command, .shift])), dryRun: false)?.command,
      ["/bin/echo", "combination"])
    XCTAssertEqual(
      CommandDecision.binding(
        for: .pinchIn, in: configuration.bindings,
        modifiers: .known(ModifierSet([.option, .control])), dryRun: false)?.command,
      ["/bin/echo", "pinch"])
  }

  func testHeldExtraModifierNeverFallsBackToPlainOrPartialBinding() throws {
    let configuration = try Configuration.load(
      Data(
        """
        [[bindings]]
        fingers = 3
        direction = "left"
        command = ["/bin/echo", "plain"]

        [[bindings]]
        fingers = 3
        direction = "left"
        modifiers = ["command"]
        command = ["/bin/echo", "command"]
        """.utf8))
    let gesture = Gesture(fingers: 3, direction: .left)

    XCTAssertNil(
      CommandDecision.binding(
        for: gesture, in: configuration.bindings,
        modifiers: .known(ModifierSet([.command, .option])), dryRun: false))
    XCTAssertNil(
      CommandDecision.binding(
        for: gesture, in: configuration.bindings,
        modifiers: .known(ModifierSet([.control])), dryRun: false))
  }

  func testUnknownModifierStateFailsClosedForPlainAndModifiedBindings() throws {
    let configuration = try Configuration.load(
      Data(
        """
        [[bindings]]
        fingers = 3
        direction = "left"
        command = ["/bin/echo", "plain"]

        [[bindings]]
        fingers = 3
        direction = "left"
        modifiers = ["command"]
        command = ["/bin/echo", "command"]
        """.utf8))
    let gesture = Gesture(fingers: 3, direction: .left)
    let state = StubModifierStateSampler(result: .unknown).sample()

    XCTAssertNil(
      CommandDecision.binding(
        for: gesture, in: configuration.bindings, modifiers: state, dryRun: false))
    XCTAssertEqual(state.displayName, "modifier state unknown")
  }

  func testPinchBindingsRemainExplicitForSupportedFingerCounts() throws {
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
        """.utf8))

    XCTAssertEqual(
      CommandDecision.binding(
        for: .pinchIn, in: configuration.bindings, modifiers: .known(.none), dryRun: false)?
        .command,
      ["/bin/echo", "in"])
    XCTAssertEqual(
      CommandDecision.binding(
        for: .pinchOut, in: configuration.bindings, modifiers: .known(.none), dryRun: false)?
        .command,
      ["/bin/echo", "out"])
    XCTAssertEqual(
      CommandDecision.binding(
        for: Gesture(fingers: 3, direction: .pinchIn),
        in: configuration.bindings, modifiers: .known(.none), dryRun: false)?.command,
      ["/bin/echo", "three-in"])
    XCTAssertEqual(
      CommandDecision.binding(
        for: Gesture(fingers: 4, direction: .pinchOut),
        in: configuration.bindings, modifiers: .known(.none), dryRun: false)?.command,
      ["/bin/echo", "four-out"])
    XCTAssertEqual(
      CommandDecision.binding(
        for: Gesture(fingers: 5, direction: .pinchIn),
        in: configuration.bindings, modifiers: .known(.none), dryRun: false)?.command,
      ["/bin/echo", "five-in"])
    XCTAssertNil(
      CommandDecision.binding(
        for: .pinchIn, in: configuration.bindings, modifiers: .known(.none), dryRun: true))
  }

  func testListenAndDryRunNeverSelectBindingsWithAnyModifierState() throws {
    let configuration = try Configuration.load(
      Data(
        """
        [[bindings]]
        fingers = 3
        direction = "left"
        modifiers = ["command"]
        command = ["/bin/echo"]
        """.utf8))
    let gesture = Gesture(fingers: 3, direction: .left)

    for state in [ModifierSample.known(.none), .known(ModifierSet([.command])), .unknown] {
      XCTAssertNil(
        CommandDecision.binding(
          for: gesture, in: configuration.bindings, modifiers: state, dryRun: true))
    }
  }
}

private struct StubModifierStateSampler: ModifierStateSampling {
  let result: ModifierSample

  func sample() -> ModifierSample { result }
}
