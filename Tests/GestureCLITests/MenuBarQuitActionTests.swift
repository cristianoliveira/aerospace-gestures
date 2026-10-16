import AppKit
import XCTest

@testable import GestureCLI

@MainActor
final class MenuBarQuitActionTests: XCTestCase {
  func testQuitMenuItemInvokesProvidedShutdownAction() {
    var quitCount = 0
    let quitAction = MenuBarQuitAction(onQuit: { quitCount += 1 })

    XCTAssertEqual(quitAction.menuItem.title, "Quit AeroSpace Gestures")
    XCTAssertTrue(quitAction.menuItem.isEnabled)
    XCTAssertTrue(quitAction.menuItem.target === quitAction)
    XCTAssertEqual(quitAction.menuItem.action, #selector(MenuBarQuitAction.quit))

    quitAction.quit()

    XCTAssertEqual(quitCount, 1)
  }
}
