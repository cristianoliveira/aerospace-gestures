import XCTest

@testable import GestureCLIPolicy

final class GestureActionPresentationTests: XCTestCase {
  func testEnabledPresentationHasMatchingAccessibleAndMenuState() {
    let presentation = GestureActionPresentation(state: .enabled)

    XCTAssertEqual(presentation.statusTitle, "Actions enabled")
    XCTAssertEqual(presentation.accessibilityLabel, "Gesture actions enabled")
    XCTAssertEqual(presentation.toggleTitle, "Disable actions")
    XCTAssertTrue(presentation.toggleIsChecked)
  }

  func testPausedPresentationSaysListenerRemainsActiveWithoutColorCue() {
    let presentation = GestureActionPresentation(state: .paused)

    XCTAssertEqual(presentation.statusTitle, "Actions paused — listener active")
    XCTAssertEqual(
      presentation.accessibilityLabel,
      "Gesture actions paused; listener remains active")
    XCTAssertEqual(presentation.toggleTitle, "Enable actions")
    XCTAssertFalse(presentation.toggleIsChecked)
    XCTAssertNotEqual(presentation.statusTitle, "Actions enabled")
  }

  func testUnavailablePresentationHasNoEnableToggleInSafeModes() {
    let presentation = GestureActionPresentation(state: .unavailable)

    XCTAssertEqual(presentation.statusTitle, "Actions unavailable")
    XCTAssertEqual(
      presentation.accessibilityLabel,
      "Gesture actions unavailable in listen or dry-run mode")
    XCTAssertNil(presentation.toggleTitle)
    XCTAssertFalse(presentation.toggleIsChecked)
  }

  func testPresentationTracksPolicyTransitions() {
    let policy = GestureActionPolicy(mode: .run)

    XCTAssertEqual(
      GestureActionPresentation(state: policy.state).statusTitle, "Actions enabled")

    policy.setActionsEnabled(false)

    XCTAssertEqual(
      GestureActionPresentation(state: policy.state).statusTitle,
      "Actions paused — listener active")
  }
}
