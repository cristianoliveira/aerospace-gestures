import GestureCore
import XCTest

@testable import GestureCLIPolicy

final class GestureActionPolicyTests: XCTestCase {
  private let gesture = Gesture(fingers: 3, direction: .down)

  func testNormalRunStartsEnabledAndAllowsCurrentGestureDispatch() {
    let policy = GestureActionPolicy(mode: .run)
    let token = policy.captureFrame(device: 7, contactCount: 3)

    XCTAssertEqual(policy.state, .enabled)
    XCTAssertTrue(policy.showsMenuBarControl)
    XCTAssertTrue(policy.isCurrent(token))
    XCTAssertTrue(policy.mayDispatch(gesture, from: token))
  }

  func testPauseInvalidatesCallbackQueuedBeforeTheToggle() {
    let policy = GestureActionPolicy(mode: .run)
    let queuedCallback = policy.captureFrame(device: 7, contactCount: 3)

    policy.setActionsEnabled(false)

    XCTAssertEqual(policy.state, .paused)
    XCTAssertFalse(policy.isCurrent(queuedCallback))
    XCTAssertFalse(policy.mayDispatch(gesture, from: queuedCallback))
  }

  func testPausedFramesRemainCurrentForRecognitionButCannotDispatch() {
    let policy = GestureActionPolicy(mode: .run)
    policy.setActionsEnabled(false)

    let pausedFrame = policy.captureFrame(device: 7, contactCount: 3)

    XCTAssertTrue(policy.isCurrent(pausedFrame))
    XCTAssertFalse(policy.mayDispatch(gesture, from: pausedFrame))
  }

  func testGestureRecognizedWhilePausedIsNotReplayedAfterResume() {
    let policy = GestureActionPolicy(mode: .run)
    policy.setActionsEnabled(false)
    let pausedGestureFrame = policy.captureFrame(device: 7, contactCount: 3)

    XCTAssertFalse(policy.mayDispatch(gesture, from: pausedGestureFrame))

    policy.setActionsEnabled(true)

    XCTAssertFalse(policy.isCurrent(pausedGestureFrame))
    XCTAssertFalse(policy.mayDispatch(gesture, from: pausedGestureFrame))
    let heldAfterResume = policy.captureFrame(device: 7, contactCount: 3)
    XCTAssertFalse(policy.mayDispatch(gesture, from: heldAfterResume))
  }

  func testRepeatedTogglesAreIdempotent() {
    let policy = GestureActionPolicy(mode: .run)
    policy.setActionsEnabled(true)
    let enabledFrame = policy.captureFrame(device: 7, contactCount: 0)
    policy.setActionsEnabled(true)

    XCTAssertEqual(policy.state, .enabled)
    XCTAssertTrue(policy.isCurrent(enabledFrame))

    policy.setActionsEnabled(false)
    let pausedFrame = policy.captureFrame(device: 7, contactCount: 0)
    policy.setActionsEnabled(false)

    XCTAssertEqual(policy.state, .paused)
    XCTAssertTrue(policy.isCurrent(pausedFrame))
    XCTAssertFalse(policy.mayDispatch(gesture, from: pausedFrame))
  }

  func testResumeDropsOldFramesAndRequiresLiftBeforeFreshDispatch() {
    let policy = GestureActionPolicy(mode: .run)
    let beforePause = policy.captureFrame(device: 7, contactCount: 3)

    policy.setActionsEnabled(false)
    policy.setActionsEnabled(true)

    let heldAfterResume = policy.captureFrame(device: 7, contactCount: 3)
    XCTAssertFalse(policy.isCurrent(beforePause))
    XCTAssertTrue(policy.isCurrent(heldAfterResume))
    XCTAssertFalse(policy.mayDispatch(gesture, from: heldAfterResume))

    _ = policy.captureFrame(device: 7, contactCount: 0)
    let freshAfterLift = policy.captureFrame(device: 7, contactCount: 3)

    XCTAssertTrue(policy.isCurrent(freshAfterLift))
    XCTAssertTrue(policy.mayDispatch(gesture, from: freshAfterLift))
  }

  func testLiftToRearmIsTrackedPerDevice() {
    let policy = GestureActionPolicy(mode: .run)
    _ = policy.captureFrame(device: 7, contactCount: 3)
    _ = policy.captureFrame(device: 9, contactCount: 3)

    policy.setActionsEnabled(false)
    policy.setActionsEnabled(true)
    _ = policy.captureFrame(device: 7, contactCount: 0)

    let freshDeviceFrame = policy.captureFrame(device: 7, contactCount: 3)
    let heldOtherDeviceFrame = policy.captureFrame(device: 9, contactCount: 3)

    XCTAssertTrue(policy.mayDispatch(gesture, from: freshDeviceFrame))
    XCTAssertFalse(policy.mayDispatch(gesture, from: heldOtherDeviceFrame))
  }

  func testListenAndDryRunCannotBeUpgradedByToggles() {
    for mode in [GestureExecutionMode.listen, .dryRun] {
      let policy = GestureActionPolicy(mode: mode)
      let frame = policy.captureFrame(device: 7, contactCount: 3)

      XCTAssertEqual(policy.state, .unavailable)
      XCTAssertFalse(policy.showsMenuBarControl)
      XCTAssertFalse(policy.mayDispatch(gesture, from: frame))

      policy.setActionsEnabled(true)
      policy.setActionsEnabled(false)

      XCTAssertEqual(policy.state, .unavailable)
      XCTAssertFalse(policy.showsMenuBarControl)
      XCTAssertFalse(policy.mayDispatch(gesture, from: frame))
    }
  }
}
