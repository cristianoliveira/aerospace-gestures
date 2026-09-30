import XCTest
import GestureCore
@testable import GestureCLIPolicy

final class CommandDecisionTests: XCTestCase {
    func testSelectsMatchingBindingOnlyWhenExecutionIsEnabled() throws {
        let configuration = try Configuration.load(Data(#"{"bindings":[{"fingers":3,"direction":"left","command":["/bin/echo"]}]}"#.utf8))
        let gesture = Gesture(fingers: 3, direction: .left)

        XCTAssertNil(CommandDecision.binding(for: gesture, in: configuration.bindings, dryRun: true))
        XCTAssertEqual(CommandDecision.binding(for: gesture, in: configuration.bindings, dryRun: false)?.command, ["/bin/echo"])
        XCTAssertNil(CommandDecision.binding(for: Gesture(fingers: 4, direction: .left), in: configuration.bindings, dryRun: false))
    }
}
