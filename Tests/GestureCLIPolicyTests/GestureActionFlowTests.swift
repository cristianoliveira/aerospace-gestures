import GestureCore
import GestureInfrastructure
import XCTest

@testable import GestureCLIPolicy

final class GestureActionFlowTests: XCTestCase {
  func testPauseKeepsRecognitionButResumeRequiresFreshSwipeAfterLift() {
    let policy = GestureActionPolicy(mode: .run)
    var detector = SwipeDetector(threshold: 0.15)
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

  func testPauseDoesNotCancelAnAlreadyRunningCommand() throws {
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

  private func contacts(x: Double) -> [Contact] {
    (0..<3).map { Contact(id: $0, x: x, y: 0.5) }
  }
}
