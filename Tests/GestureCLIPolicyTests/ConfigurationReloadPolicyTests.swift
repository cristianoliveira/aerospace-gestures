import GestureCore
import XCTest

@testable import GestureCLIPolicy

final class ConfigurationReloadPolicyTests: XCTestCase {
  func testSuccessfulReloadAtomicallyReplacesActiveConfiguration() throws {
    let original = try configuration(
      command: "/bin/echo", threshold: 0.15, debugCommandOutput: true)
    let replacement = try configuration(command: "/usr/bin/true", threshold: 0.3)
    let policy = ConfigurationReloadPolicy(initialConfiguration: original, mode: .run)
    let request = try XCTUnwrap(policy.beginReload())

    XCTAssertEqual(policy.state, .loading)
    XCTAssertEqual(policy.activeConfiguration?.threshold, 0.15)

    XCTAssertTrue(policy.completeReload(request, with: .success(replacement)))

    XCTAssertEqual(policy.activeConfiguration?.threshold, 0.3)
    XCTAssertEqual(policy.activeConfiguration?.bindings.first?.command, ["/usr/bin/true"])
    XCTAssertFalse(try XCTUnwrap(policy.activeConfiguration).debugCommandOutput)
    XCTAssertEqual(policy.state, .succeeded)
  }

  func testFailedReloadKeepsPreviousConfigurationActive() throws {
    let original = try configuration(
      command: "/bin/echo", threshold: 0.15, debugCommandOutput: true)
    let policy = ConfigurationReloadPolicy(initialConfiguration: original, mode: .run)
    let request = try XCTUnwrap(policy.beginReload())

    XCTAssertTrue(policy.completeReload(request, with: .failure("invalid TOML")))

    XCTAssertEqual(policy.activeConfiguration?.threshold, 0.15)
    XCTAssertEqual(policy.activeConfiguration?.bindings.first?.command, ["/bin/echo"])
    XCTAssertTrue(try XCTUnwrap(policy.activeConfiguration).debugCommandOutput)
    XCTAssertEqual(policy.state, .failed("invalid TOML"))
  }

  func testOnlyLatestActiveRequestCanComplete() throws {
    let original = try configuration(command: "/bin/echo", threshold: 0.15)
    let firstReplacement = try configuration(command: "/usr/bin/true", threshold: 0.3)
    let latestReplacement = try configuration(command: "/bin/false", threshold: 0.4)
    let policy = ConfigurationReloadPolicy(initialConfiguration: original, mode: .run)
    let firstRequest = try XCTUnwrap(policy.beginReload())

    XCTAssertNil(policy.beginReload(), "Concurrent reload attempts must be rejected")
    XCTAssertTrue(policy.completeReload(firstRequest, with: .failure("first attempt failed")))
    let latestRequest = try XCTUnwrap(policy.beginReload())

    XCTAssertFalse(policy.completeReload(firstRequest, with: .success(firstReplacement)))
    XCTAssertEqual(policy.activeConfiguration?.bindings.first?.command, ["/bin/echo"])
    XCTAssertTrue(policy.completeReload(latestRequest, with: .success(latestReplacement)))
    XCTAssertEqual(policy.activeConfiguration?.bindings.first?.command, ["/bin/false"])
  }

  func testListenAndDryRunCannotReloadConfiguration() throws {
    let configuration = try configuration(command: "/bin/echo", threshold: 0.15)

    for mode in [GestureExecutionMode.listen, .dryRun] {
      let policy = ConfigurationReloadPolicy(initialConfiguration: configuration, mode: mode)

      XCTAssertFalse(policy.canReload)
      XCTAssertNil(policy.beginReload())
      XCTAssertEqual(policy.activeConfiguration?.threshold, 0.15)
      XCTAssertEqual(policy.state, .unavailable)
    }
  }

  private func configuration(
    command: String, threshold: Double, debugCommandOutput: Bool = false
  ) throws -> Configuration {
    try Configuration.load(
      Data(
        """
        threshold = \(threshold)
        debug_command_output = \(debugCommandOutput)

        [[bindings]]
        fingers = 3
        direction = "down"
        command = ["\(command)"]
        """.utf8))
  }
}
