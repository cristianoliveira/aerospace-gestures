import XCTest

@testable import GestureCore

final class GestureCoreTests: XCTestCase {
  private func points(_ count: Int = 3, x: Double, y: Double = 0.5) -> [Contact] {
    (0..<count).map { Contact(id: $0, x: x, y: y) }
  }

  func testSwipeEmitsOnceUntilAllFingersLift() {
    var detector = SwipeDetector(threshold: 0.15)
    XCTAssertNil(detector.update(points(x: 0.2)))
    XCTAssertEqual(detector.update(points(x: 0.4)), Gesture(fingers: 3, direction: .right))
    XCTAssertNil(detector.update(points(x: 0.7)))
    XCTAssertNil(detector.update([]))
    XCTAssertNil(detector.update(points(x: 0.7)))
    XCTAssertEqual(detector.update(points(x: 0.4)), Gesture(fingers: 3, direction: .left))
  }

  func testThreeFingerDownSwipeEmitsOnceAndRearmsAfterLift() {
    var detector = SwipeDetector(threshold: 0.15)
    let expected = Gesture(fingers: 3, direction: .down)

    XCTAssertNil(detector.update(points(x: 0.5, y: 0.8)))
    XCTAssertNil(detector.update(points(x: 0.5, y: 0.75)))
    XCTAssertEqual(detector.update(points(x: 0.5, y: 0.5)), expected)
    XCTAssertNil(detector.update(points(x: 0.5, y: 0.2)))

    XCTAssertNil(detector.update([]))
    XCTAssertNil(detector.update(points(x: 0.5, y: 0.8)))
    XCTAssertEqual(detector.update(points(x: 0.5, y: 0.5)), expected)
  }

  func testFourFingerVerticalSwipeAndSmallMovement() {
    var detector = SwipeDetector(threshold: 0.15)
    XCTAssertNil(detector.update(points(4, x: 0.5, y: 0.2)))
    XCTAssertNil(detector.update(points(4, x: 0.5, y: 0.25)))
    XCTAssertEqual(detector.update(points(4, x: 0.5, y: 0.5)), Gesture(fingers: 4, direction: .up))
  }

  func testTwoFingersAndDiagonalDoNotTrigger() {
    var detector = SwipeDetector(threshold: 0.15)
    XCTAssertNil(detector.update(points(2, x: 0.1)))
    XCTAssertNil(detector.update(points(2, x: 0.8)))
    XCTAssertNil(detector.update(points(x: 0.1, y: 0.1)))
    XCTAssertNil(detector.update(points(x: 0.4, y: 0.4)))
  }

  func testChangingContactsResetsOriginRatherThanCreatingSwipe() {
    var detector = SwipeDetector(threshold: 0.15)
    XCTAssertNil(detector.update(points(x: 0.1)))
    XCTAssertNil(detector.update(points(4, x: 0.8)))
    XCTAssertEqual(detector.update(points(4, x: 0.6)), Gesture(fingers: 4, direction: .left))
  }

  func testPinchingDoesNotCountAsSwipe() {
    var detector = SwipeDetector(threshold: 0.15)
    XCTAssertNil(detector.update(points(x: 0.5)))
    XCTAssertNil(
      detector.update([
        Contact(id: 0, x: 0.1, y: 0.5),
        Contact(id: 1, x: 0.9, y: 0.5),
        Contact(id: 2, x: 0.9, y: 0.5),
      ]))
  }

  func testFiveFingerDownSwipeDoesNotRearmWhenOnlySomeFingersLift() {
    var detector = SwipeDetector(threshold: 0.15)
    XCTAssertNil(detector.update(points(5, x: 0.5, y: 0.8)))
    XCTAssertEqual(
      detector.update(points(5, x: 0.5, y: 0.5)), Gesture(fingers: 5, direction: .down))
    XCTAssertNil(detector.update(points(3, x: 0.5, y: 0.5)))
    XCTAssertNil(detector.update(points(3, x: 0.5, y: 0.1)))
  }

  func testInvalidPositionsResetTheOrigin() {
    var detector = SwipeDetector(threshold: 0.15)
    XCTAssertNil(detector.update(points(x: 0.1)))
    XCTAssertNil(detector.update(points(x: .nan)))
    XCTAssertNil(detector.update(points(x: 0.8)))
    XCTAssertEqual(detector.update(points(x: 0.5)), Gesture(fingers: 3, direction: .left))
  }

  func testConfigurationRejectsUnsafeOrAmbiguousBindings() throws {
    let invalid = [
      "threshold = 0\nbindings = []",
      """
      [[bindings]]
      fingers = 2
      direction = "left"
      command = ["/bin/echo"]
      """,
      """
      [[bindings]]
      fingers = 3
      direction = "left"
      command = []
      """,
      """
      [[bindings]]
      fingers = 3
      direction = "left"
      command = ["echo"]
      """,
      """
      [[bindings]]
      fingers = 3
      direction = "left"
      command = ["/bin/echo"]

      [[bindings]]
      fingers = 3
      direction = "left"
      command = ["/bin/ls"]
      """,
    ]
    for toml in invalid {
      XCTAssertThrowsError(try Configuration.load(Data(toml.utf8)))
    }

    let config = try Configuration.load(
      Data(
        """
        [[bindings]]
        fingers = 3
        direction = "left"
        command = ["/bin/echo", "hello; not a shell"]
        """.utf8))
    XCTAssertEqual(config.threshold, 0.15)
    XCTAssertEqual(config.bindings[0].command, ["/bin/echo", "hello; not a shell"])
  }

  func testCommandOutputDebuggingIsOptInAndDefaultsOff() throws {
    let defaultConfiguration = try Configuration.load(Data("bindings = []".utf8))
    XCTAssertFalse(defaultConfiguration.debugCommandOutput)

    let enabledConfiguration = try Configuration.load(
      Data("debug_command_output = true\nbindings = []".utf8))
    XCTAssertTrue(enabledConfiguration.debugCommandOutput)

    let bindingScopedConfiguration = try Configuration.load(
      Data(
        """
        [[bindings]]
        fingers = 3
        direction = "down"
        command = ["/bin/echo"]
        debug_command_output = true
        """.utf8))
    XCTAssertFalse(bindingScopedConfiguration.debugCommandOutput)
  }

  func testConfigurationRejectsMalformedTOMLAndLegacyJSON() {
    XCTAssertThrowsError(try Configuration.load(Data("[[bindings]\n".utf8))) { error in
      XCTAssertTrue(String(describing: error).contains("invalid TOML at line"))
    }
    XCTAssertThrowsError(
      try Configuration.load(
        Data(#"{"bindings":[{"fingers":3,"direction":"left","command":["/bin/echo"]}]}"#.utf8)))
  }

  func testConfigurationRejectsInvalidUTF8() {
    XCTAssertThrowsError(try Configuration.load(Data([0xFF]))) { error in
      XCTAssertTrue(String(describing: error).contains("valid UTF-8"))
    }
  }
}
