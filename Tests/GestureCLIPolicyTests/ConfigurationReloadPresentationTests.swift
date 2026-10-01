import XCTest

@testable import GestureCLIPolicy

final class ConfigurationReloadPresentationTests: XCTestCase {
  func testLoadingPresentationDisablesAnotherReload() {
    let presentation = ConfigurationReloadPresentation(state: .loading, canReload: true)

    XCTAssertFalse(presentation.reloadIsEnabled)
    XCTAssertEqual(presentation.feedbackMessage, "Reloading configuration…")
  }

  func testSuccessAndFailureHaveVisibleMenuFeedback() {
    let success = ConfigurationReloadPresentation(state: .succeeded, canReload: true)
    let failure = ConfigurationReloadPresentation(
      state: .failed("invalid TOML"), canReload: true)

    XCTAssertTrue(success.reloadIsEnabled)
    XCTAssertEqual(success.feedbackMessage, "Configuration reloaded")
    XCTAssertTrue(failure.reloadIsEnabled)
    XCTAssertEqual(failure.feedbackMessage, "Reload failed: invalid TOML")
  }

  func testSafeModesHideReloadFeedbackAndDisableReload() {
    let presentation = ConfigurationReloadPresentation(state: .unavailable, canReload: false)

    XCTAssertFalse(presentation.reloadIsEnabled)
    XCTAssertNil(presentation.feedbackMessage)
  }
}
