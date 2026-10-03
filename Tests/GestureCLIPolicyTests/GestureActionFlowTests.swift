import Foundation
import GestureCore
import GestureInfrastructure
import XCTest

@testable import GestureCLIPolicy

final class GestureActionFlowTests: XCTestCase {
  func testPauseKeepsRecognitionButResumeRequiresFreshSwipeAfterLift() {
    let policy = GestureActionPolicy(mode: .run)
    var detector = GestureDetector(threshold: 0.15)
    var dispatched: [Gesture] = []

    func process(_ contacts: [Contact]) -> Gesture? {
      let token = policy.captureFrame(device: 1, contactCount: contacts.count)
      guard policy.isCurrent(token) else { return nil }

      let gesture = detector.update(contacts)
      if let gesture, policy.mayDispatch(gesture, from: token) {
        dispatched.append(gesture)
      }
      return gesture
    }

    XCTAssertNil(process(contacts(x: 0.8)))
    policy.setActionsEnabled(false)
    XCTAssertEqual(process(contacts(x: 0.4)), Gesture(fingers: 3, direction: .left))
    XCTAssertTrue(dispatched.isEmpty)

    policy.setActionsEnabled(true)
    XCTAssertNil(process(contacts(x: 0.2)))
    XCTAssertTrue(dispatched.isEmpty)

    XCTAssertNil(process([]))
    XCTAssertNil(process(contacts(x: 0.8)))
    XCTAssertEqual(process(contacts(x: 0.4)), Gesture(fingers: 3, direction: .left))
    XCTAssertEqual(dispatched, [Gesture(fingers: 3, direction: .left)])
  }

  func testPinchBindingInRunModeRespectsPauseAndRequiresLiftBeforeDispatch() throws {
    let configuration = try Configuration.load(
      Data(
        """
        [[bindings]]
        fingers = 2
        direction = "in"
        command = ["/bin/echo", "pinched"]
        """.utf8))
    let policy = GestureActionPolicy(mode: .run)
    var detector = GestureDetector(threshold: 0.15, pinchThreshold: 0.2)
    var dispatched: [[String]] = []

    func process(_ contacts: [Contact]) -> Gesture? {
      let token = policy.captureFrame(device: 1, contactCount: contacts.count)
      guard policy.isCurrent(token) else { return nil }

      let gesture = detector.update(contacts)
      if let gesture,
        let binding = CommandDecision.binding(
          for: gesture, in: configuration.bindings, dryRun: false),
        policy.mayDispatch(gesture, from: token)
      {
        dispatched.append(binding.command)
      }
      return gesture
    }

    XCTAssertNil(process(pinchContacts((0.4, 0.5), (0.6, 0.5))))
    policy.setActionsEnabled(false)
    XCTAssertEqual(process(pinchContacts((0.43, 0.5), (0.57, 0.5))), .pinchIn)
    XCTAssertTrue(dispatched.isEmpty)

    policy.setActionsEnabled(true)
    XCTAssertNil(process([]))
    XCTAssertNil(process(pinchContacts((0.4, 0.5), (0.6, 0.5))))
    XCTAssertEqual(process(pinchContacts((0.43, 0.5), (0.57, 0.5))), .pinchIn)
    XCTAssertEqual(dispatched, [["/bin/echo", "pinched"]])
  }

  func testThreeFingerPinchDispatchesItsBindingAlongsideSameCountSwipe() throws {
    let configuration = try Configuration.load(
      Data(
        """
        [[bindings]]
        fingers = 3
        direction = "in"
        command = ["/bin/echo", "pinch"]

        [[bindings]]
        fingers = 3
        direction = "left"
        command = ["/bin/echo", "swipe"]

        [[bindings]]
        fingers = 4
        direction = "in"
        command = ["/bin/echo", "four-finger-pinch"]
        """.utf8))
    let policy = GestureActionPolicy(mode: .run)
    var detector = GestureDetector(threshold: 0.15, pinchThreshold: 0.2)

    XCTAssertNil(detector.update(radialContacts(count: 3, radius: 0.2)))
    let frame = policy.captureFrame(device: 1, contactCount: 3)
    guard let gesture = detector.update(radialContacts(count: 3, radius: 0.14)) else {
      XCTFail("three-finger pinch should be recognized")
      return
    }

    XCTAssertEqual(gesture, Gesture(fingers: 3, direction: .pinchIn))
    XCTAssertEqual(gesture.displayName, "3-finger pinch in")
    XCTAssertTrue(policy.mayDispatch(gesture, from: frame))
    XCTAssertEqual(
      CommandDecision.binding(for: gesture, in: configuration.bindings, dryRun: false)?.command,
      ["/bin/echo", "pinch"])
    XCTAssertNil(detector.update(radialContacts(count: 3, radius: 0.12)))
  }

  func testReloadInvalidatesQueuedFramesPreservesPauseAndRequiresLift() {
    let policy = GestureActionPolicy(mode: .run)
    _ = policy.captureFrame(device: 1, contactCount: 3)
    policy.setActionsEnabled(false)
    let queuedWhilePaused = policy.captureFrame(device: 1, contactCount: 3)

    policy.invalidateFramesForConfigurationReload()

    XCTAssertEqual(policy.state, .paused)
    XCTAssertFalse(policy.isCurrent(queuedWhilePaused))
    XCTAssertFalse(
      policy.mayDispatch(Gesture(fingers: 3, direction: .down), from: queuedWhilePaused))

    policy.setActionsEnabled(true)
    let heldAfterResume = policy.captureFrame(device: 1, contactCount: 3)
    XCTAssertFalse(policy.mayDispatch(Gesture(fingers: 3, direction: .down), from: heldAfterResume))

    _ = policy.captureFrame(device: 1, contactCount: 0)
    let freshAfterLift = policy.captureFrame(device: 1, contactCount: 3)
    XCTAssertTrue(policy.mayDispatch(Gesture(fingers: 3, direction: .down), from: freshAfterLift))
  }

  func testPauseAndReloadDoNotCancelAnAlreadyRunningCommand() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let script = directory.appendingPathComponent("finish-command.sh")
    let ready = directory.appendingPathComponent("command-ready")
    let release = directory.appendingPathComponent("release-command")
    let finished = directory.appendingPathComponent("command-finished")
    let scriptBody = """
      #!/bin/sh
      /usr/bin/touch "$1"
      while [ ! -e "$2" ]; do /usr/bin/sleep 0.01; done
      /usr/bin/touch "$3"
      """
    try Data(scriptBody.utf8).write(to: script)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: script.path)

    let policy = GestureActionPolicy(mode: .run)
    let frame = policy.captureFrame(device: 1, contactCount: 3)
    let runner = CommandRunner(timeout: 10)
    let commandFinished = expectation(description: "already-running command finishes after pause")

    XCTAssertTrue(policy.mayDispatch(Gesture(fingers: 3, direction: .down), from: frame))
    XCTAssertTrue(
      runner.run([script.path, ready.path, release.path, finished.path]) { _ in
        commandFinished.fulfill()
      })
    XCTAssertTrue(waitForFile(ready, timeout: 3), "command must be blocked at the ready handshake")

    policy.setActionsEnabled(false)
    XCTAssertEqual(policy.state, .paused)
    XCTAssertFalse(FileManager.default.fileExists(atPath: finished.path))

    let original = try Configuration.load(Data("bindings = []".utf8))
    let replacement = try Configuration.load(
      Data("threshold = 0.3\nbindings = []".utf8))
    let reloadPolicy = ConfigurationReloadPolicy(initialConfiguration: original, mode: .run)
    let reload = try XCTUnwrap(reloadPolicy.beginReload())
    XCTAssertTrue(reloadPolicy.completeReload(reload, with: .success(replacement)))
    policy.invalidateFramesForConfigurationReload()

    try Data().write(to: release)
    wait(for: [commandFinished], timeout: 3)

    XCTAssertTrue(FileManager.default.fileExists(atPath: finished.path))
  }

  private func waitForFile(_ url: URL, timeout: TimeInterval) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if FileManager.default.fileExists(atPath: url.path) { return true }
      Thread.sleep(forTimeInterval: 0.01)
    }
    return FileManager.default.fileExists(atPath: url.path)
  }

  private func pinchContacts(
    _ first: (Double, Double), _ second: (Double, Double)
  ) -> [Contact] {
    [Contact(id: 1, x: first.0, y: first.1), Contact(id: 2, x: second.0, y: second.1)]
  }

  private func radialContacts(count: Int, radius: Double) -> [Contact] {
    (0..<count).map { index in
      let angle = 2 * Double.pi * Double(index) / Double(count)
      return Contact(
        id: index + 1,
        x: 0.5 + radius * cos(angle),
        y: 0.5 + radius * sin(angle))
    }
  }

  private func contacts(x: Double) -> [Contact] {
    (0..<3).map { Contact(id: $0, x: x, y: 0.5) }
  }
}
