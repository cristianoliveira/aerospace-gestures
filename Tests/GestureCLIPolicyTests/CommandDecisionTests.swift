import GestureCore
import XCTest

@testable import GestureCLIPolicy

final class CommandDecisionTests: XCTestCase {
  func testAppGesturePreferencePersistsBooleanAcrossPolicyInstances() {
    let suiteName = "com.aerospace-gestures.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let firstStore = AppGesturePreferenceStore(defaults: defaults)

    XCTAssertNil(firstStore.load())
    let firstPolicy = AppGesturePolicy(
      enabled: firstStore.load() ?? true,
      onChange: { firstStore.save($0) })
    XCTAssertTrue(firstPolicy.isEnabled)
    firstPolicy.setEnabled(false)

    let secondStore = AppGesturePreferenceStore(defaults: UserDefaults(suiteName: suiteName)!)
    let secondPolicy = AppGesturePolicy(
      enabled: secondStore.load() ?? true,
      onChange: { secondStore.save($0) })
    XCTAssertFalse(secondPolicy.isEnabled)
    XCTAssertTrue(defaults.object(forKey: "appScopedGesturesEnabled") is Bool)
    XCTAssertFalse(defaults.bool(forKey: "appScopedGesturesEnabled"))

    secondPolicy.setEnabled(true)
    let thirdStore = AppGesturePreferenceStore(defaults: UserDefaults(suiteName: suiteName)!)
    XCTAssertEqual(thirdStore.load(), true)
  }

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

  func testAppSpecificBindingOverridesGenericAndFallsBackForOtherAppsOrWhenDisabled() throws {
    let configuration = try Configuration.load(
      Data(
        """
        [[bindings]]
        fingers = 3
        direction = "left"
        command = ["/bin/echo", "generic"]

        [[bindings]]
        fingers = 3
        direction = "left"
        app = "com.example.Editor"
        command = ["/bin/echo", "editor"]
        """.utf8))
    let gesture = Gesture(fingers: 3, direction: .left)
    func select(_ app: String?, enabled: Bool = true) -> [String]? {
      CommandDecision.binding(
        for: gesture, in: configuration.bindings,
        modifiers: .known(.none), dryRun: false, frontmostApp: app,
        appBindingsEnabled: enabled)?.command
    }

    XCTAssertEqual(select("com.example.Editor"), ["/bin/echo", "editor"])
    XCTAssertEqual(select("com.example.editor"), ["/bin/echo", "generic"])
    XCTAssertEqual(select(nil), ["/bin/echo", "generic"])
    XCTAssertEqual(select("com.example.Editor", enabled: false), ["/bin/echo", "generic"])
  }

  func testUnknownFrontmostAppAtTouchDownCannotBecomeScopedMidGesture() {
    var tracker = AppGestureFocusTracker()
    XCTAssertEqual(
      tracker.observe(contactCount: 2, frontmostApp: nil, appBindingsEnabled: true).matchingApp, nil
    )
    XCTAssertEqual(
      tracker.observe(contactCount: 3, frontmostApp: "com.example.Editor", appBindingsEnabled: true)
        .matchingApp, nil)
    _ = tracker.observe(contactCount: 0, frontmostApp: nil, appBindingsEnabled: true)
    XCTAssertEqual(
      tracker.observe(contactCount: 2, frontmostApp: "com.example.Editor", appBindingsEnabled: true)
        .matchingApp, "com.example.Editor")
  }

  func testFocusChangeInvalidatesScopeUntilFullLift() {
    var tracker = AppGestureFocusTracker()
    XCTAssertTrue(
      tracker.observe(contactCount: 2, frontmostApp: "com.example.Editor", appBindingsEnabled: true)
        .mayDispatch)
    XCTAssertFalse(
      tracker.observe(contactCount: 2, frontmostApp: "com.example.Other", appBindingsEnabled: true)
        .mayDispatch)
    XCTAssertFalse(
      tracker.observe(contactCount: 2, frontmostApp: "com.example.Editor", appBindingsEnabled: true)
        .mayDispatch)
    _ = tracker.observe(contactCount: 0, frontmostApp: nil, appBindingsEnabled: true)
    XCTAssertTrue(
      tracker.observe(contactCount: 2, frontmostApp: "com.example.Editor", appBindingsEnabled: true)
        .mayDispatch)
  }

  func testDisabledAppScopesDoNotCancelGenericGesturesOnFocusChanges() {
    var tracker = AppGestureFocusTracker()
    XCTAssertTrue(
      tracker.observe(
        contactCount: 2, frontmostApp: nil, appBindingsEnabled: false
      ).mayDispatch)
    XCTAssertTrue(
      tracker.observe(
        contactCount: 2, frontmostApp: nil, appBindingsEnabled: false
      ).mayDispatch)
    XCTAssertNil(
      tracker.observe(
        contactCount: 2, frontmostApp: "com.example.Editor", appBindingsEnabled: false
      )
      .matchingApp)
  }

  func testTurningScopedGesturesBackOnRequiresANewContactSequence() {
    var tracker = AppGestureFocusTracker()
    XCTAssertEqual(
      tracker.observe(contactCount: 2, frontmostApp: "com.example.Editor", appBindingsEnabled: true)
        .matchingApp, "com.example.Editor")
    XCTAssertNil(
      tracker.observe(
        contactCount: 2, frontmostApp: "com.example.Editor", appBindingsEnabled: false
      ).matchingApp)
    XCTAssertNil(
      tracker.observe(contactCount: 2, frontmostApp: "com.example.Editor", appBindingsEnabled: true)
        .matchingApp)
    _ = tracker.observe(contactCount: 0, frontmostApp: nil, appBindingsEnabled: true)
    XCTAssertEqual(
      tracker.observe(contactCount: 2, frontmostApp: "com.example.Editor", appBindingsEnabled: true)
        .matchingApp, "com.example.Editor")
  }

  func testScopedBindingNeverBecomesGlobalWhenAppToggleIsOff() throws {
    let configuration = try Configuration.load(
      Data(
        """
        [[bindings]]
        fingers = 3
        direction = "left"
        app = "com.example.Editor"
        command = ["/bin/echo", "editor"]
        """.utf8))
    XCTAssertNil(
      CommandDecision.binding(
        for: Gesture(fingers: 3, direction: .left),
        in: configuration.bindings, modifiers: .known(.none), dryRun: false,
        frontmostApp: "com.example.Editor", appBindingsEnabled: false))
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
