import Darwin
import XCTest

@testable import GestureInfrastructure

final class CommandRunnerTests: XCTestCase {
  func testPassesArgumentsLiterallyWithoutShellExpansion() {
    let completed = expectation(description: "literal argument accepted")
    let runner = CommandRunner()
    XCTAssertTrue(
      runner.run(["/bin/test", "-n", "$(exit 42)"]) { message in
        XCTAssertEqual(message, "Command exited with status 0")
        completed.fulfill()
      })
    wait(for: [completed], timeout: 3)
  }

  func testChildOutputIsNotIncludedInCompletionMessage() {
    let completed = expectation(description: "child output remains discarded")
    let runner = CommandRunner()
    let command = "/bin/sh -c 'printf secret-stdout; printf secret-stderr >&2'"

    XCTAssertTrue(
      runner.run(["/bin/sh", "-c", "printf secret-stdout; printf secret-stderr >&2"]) { message in
        XCTAssertEqual(message, "Command exited with status 0")
        XCTAssertFalse(message.contains("secret-stdout"))
        XCTAssertFalse(message.contains("secret-stderr"))
        XCTAssertFalse(message.contains(command))
        completed.fulfill()
      })
    wait(for: [completed], timeout: 3)
  }

  func testCapturesStdoutAndStderrWithoutAddingOutputToCompletionMessage() {
    let completed = expectation(description: "captured output command completes")
    let outputLock = NSLock()
    var stdout = Data()
    var stderr = Data()
    let runner = CommandRunner()

    XCTAssertTrue(
      runner.run(
        ["/bin/sh", "-c", "printf 'from stdout'; printf 'from stderr' >&2"],
        outputHandler: { stream, data in
          outputLock.lock()
          defer { outputLock.unlock() }
          switch stream {
          case .stdout: stdout.append(data)
          case .stderr: stderr.append(data)
          }
        }
      ) { message in
        XCTAssertEqual(message, "Command exited with status 0")
        completed.fulfill()
      })
    wait(for: [completed], timeout: 3)

    outputLock.lock()
    defer { outputLock.unlock() }
    XCTAssertEqual(String(data: stdout, encoding: .utf8), "from stdout")
    XCTAssertEqual(String(data: stderr, encoding: .utf8), "from stderr")
  }

  func testCapturesOnlyTheConfiguredMaximumAndStillDrainsBothPipes() {
    let completed = expectation(description: "large output command completes")
    let outputLock = NSLock()
    var captured = Data()
    let maximumOutputBytes = 4096
    let runner = CommandRunner(maximumOutputBytes: maximumOutputBytes)

    XCTAssertTrue(
      runner.run(
        ["/bin/sh", "-c", "head -c 131072 /dev/zero; head -c 131072 /dev/zero >&2"],
        outputHandler: { _, data in
          outputLock.lock()
          captured.append(data)
          outputLock.unlock()
        }
      ) { message in
        XCTAssertEqual(message, "Command exited with status 0")
        completed.fulfill()
      })
    wait(for: [completed], timeout: 3)

    outputLock.lock()
    defer { outputLock.unlock() }
    XCTAssertLessThanOrEqual(captured.count, maximumOutputBytes + 64)
  }

  func testReportsNonzeroExitStatus() {
    let completed = expectation(description: "nonzero exit reported")
    let runner = CommandRunner()

    XCTAssertTrue(
      runner.run(["/usr/bin/false"]) { message in
        XCTAssertEqual(message, "Command exited with status 1")
        completed.fulfill()
      })
    wait(for: [completed], timeout: 3)
  }

  func testLaunchFailureAllowsNextCommand() {
    let runner = CommandRunner()
    var error = ""
    XCTAssertFalse(runner.run(["/nonexistent/aerospace-gestures-test"]) { error = $0 })
    XCTAssertTrue(error.hasPrefix("Cannot launch command:"))

    let completed = expectation(description: "next command completes")
    XCTAssertTrue(
      runner.run(["/usr/bin/true"]) { message in
        XCTAssertEqual(message, "Command exited with status 0")
        completed.fulfill()
      })
    wait(for: [completed], timeout: 3)
  }

  func testBusyCommandsAreDroppedAndLongCommandTimesOut() {
    let completed = expectation(description: "sleep terminated")
    let runner = CommandRunner(timeout: 0.05)
    XCTAssertTrue(
      runner.run(["/bin/sleep", "30"]) { message in
        XCTAssertNotEqual(message, "Command exited with status 0")
        completed.fulfill()
      })
    XCTAssertFalse(runner.run(["/usr/bin/true"]) { _ in XCTFail("Busy command must not run") })
    wait(for: [completed], timeout: 3)
  }

  func testStopTerminatesActiveCommand() {
    let completed = expectation(description: "active command stopped")
    let runner = CommandRunner(timeout: 30)
    XCTAssertTrue(
      runner.run(["/bin/sleep", "30"], outputHandler: { _, _ in }) { message in
        XCTAssertNotEqual(message, "Command exited with status 0")
        completed.fulfill()
      })

    runner.stop()
    wait(for: [completed], timeout: 3)
  }

  func testStopEscalatesWhenCommandIgnoresTermination() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let pidFile = directory.appendingPathComponent("child.pid")
    let temporaryPIDFile = directory.appendingPathComponent("child.pid.tmp")
    let completed = expectation(description: "unresponsive child killed during stop")
    let runner = CommandRunner(timeout: 30)
    var stopped = false
    var childPID: pid_t?
    defer {
      if !stopped { runner.stop() }
      if let childPID { kill(childPID, SIGKILL) }
    }
    let script =
      "trap '' TERM; printf '%s\\n' \"$$\" > '\(temporaryPIDFile.path)'; mv '\(temporaryPIDFile.path)' '\(pidFile.path)'; exec /bin/sleep 30"

    XCTAssertTrue(runner.run(["/bin/sh", "-c", script], outputHandler: { _, _ in }) { _ in })
    let deadline = Date().addingTimeInterval(3)
    while Date() < deadline {
      if let contents = try? String(contentsOf: pidFile, encoding: .utf8),
        let parsedPID = pid_t(contents.trimmingCharacters(in: .whitespacesAndNewlines))
      {
        childPID = parsedPID
        break
      }
      Thread.sleep(forTimeInterval: 0.01)
    }
    guard let processID = childPID else {
      XCTFail("child did not publish its ready PID")
      return
    }

    runner.stop {
      stopped = true
      completed.fulfill()
    }
    wait(for: [completed], timeout: 3)

    errno = 0
    XCTAssertEqual(kill(processID, 0), -1)
    XCTAssertEqual(errno, ESRCH)
  }

  func testTimeoutEscalatesWhenCommandIgnoresTermination() {
    let completed = expectation(description: "unresponsive command killed")
    let runner = CommandRunner(timeout: 0.05)
    XCTAssertTrue(
      runner.run(
        ["/bin/sh", "-c", "printf started; trap '' TERM; exec /bin/sleep 30"],
        outputHandler: { _, _ in }
      ) { message in
        XCTAssertNotEqual(message, "Command exited with status 0")
        completed.fulfill()
      })

    wait(for: [completed], timeout: 3)
  }
}
