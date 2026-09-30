import XCTest
@testable import GestureCore

final class CommandRunnerTests: XCTestCase {
    func testPassesArgumentsLiterallyWithoutShellExpansion() {
        let completed = expectation(description: "literal argument accepted")
        let runner = CommandRunner()
        XCTAssertTrue(runner.run(["/bin/test", "-n", "$(exit 42)"]) { message in
            XCTAssertEqual(message, "Command exited with status 0")
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
        XCTAssertTrue(runner.run(["/usr/bin/true"]) { message in
            XCTAssertEqual(message, "Command exited with status 0")
            completed.fulfill()
        })
        wait(for: [completed], timeout: 3)
    }

    func testBusyCommandsAreDroppedAndLongCommandTimesOut() {
        let completed = expectation(description: "sleep terminated")
        let runner = CommandRunner(timeout: 0.05)
        XCTAssertTrue(runner.run(["/bin/sleep", "30"]) { message in
            XCTAssertNotEqual(message, "Command exited with status 0")
            completed.fulfill()
        })
        XCTAssertFalse(runner.run(["/usr/bin/true"]) { _ in XCTFail("Busy command must not run") })
        wait(for: [completed], timeout: 3)
    }
}
