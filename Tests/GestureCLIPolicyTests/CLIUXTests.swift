import GestureCore
import XCTest

@testable import GestureCLIPolicy

final class CLIUXTests: XCTestCase {
  private let environment = CLIEnvironment(
    values: [:],
    homeDirectory: URL(fileURLWithPath: "/tmp/home", isDirectory: true),
    currentDirectory: URL(fileURLWithPath: "/tmp/work tree", isDirectory: true))

  // MARK: version

  func testVersionFlagAndCommandParseToVersionRequest() throws {
    XCTAssertEqual(try CLIRequest.parse(["--version"], in: environment), .version)
    XCTAssertEqual(try CLIRequest.parse(["version"], in: environment), .version)
  }

  func testVersionConstantMatchesChangelogReleaseSection() throws {
    XCTAssertEqual(CLIVersion.current, "0.2.0")
    let changelog = try String(
      contentsOf: URL(fileURLWithPath: Self.repositoryRoot().appendingPathComponent("CHANGELOG.md").path),
      encoding: .utf8)
    XCTAssertTrue(
      changelog.contains("## v\(CLIVersion.current)"),
      "CHANGELOG.md must document a section for the binary version \(CLIVersion.current)")
  }

  // MARK: help routing

  func testHelpCommandRoutesToRootAndKnownCommands() throws {
    XCTAssertEqual(try CLIRequest.parse(["help"], in: environment), .help(.root))
    XCTAssertEqual(try CLIRequest.parse(["help", "check"], in: environment), .help(.check))
    XCTAssertEqual(try CLIRequest.parse(["help", "service"], in: environment), .help(.service))
  }

  func testHelpWithUnknownCommandThrowsUnknownCommandHint() throws {
    XCTAssertThrowsError(try CLIRequest.parse(["help", "bogus"], in: environment)) { error in
      XCTAssertTrue(String(describing: error).contains("Unknown command: bogus"))
      XCTAssertTrue(String(describing: error).contains("Available commands"))
    }
  }

  func testHelpRejectsExtraArguments() {
    XCTAssertThrowsError(try CLIRequest.parse(["help", "check", "extra"], in: environment))
  }

  // MARK: options are never mistaken for a config path

  func testUnknownOptionIsRejectedInsteadOfBecomingAConfigPath() {
    for arguments in [["check", "--dry-run"], ["init", "-x"], ["run", "--dri"], ["service", "--quiet"]] {
      XCTAssertThrowsError(try CLIRequest.parse(arguments, in: environment)) { error in
        XCTAssertTrue(
          String(describing: error).contains("Unknown option"),
          "expected an unknown-option hint for \(arguments), got: \(error)")
      }
    }
  }

  func testRunAcceptsDryRunFlagInAnyPosition() throws {
    let leading = try CLIRequest.parse(["run", "--dry-run", "config.toml"], in: environment)
    let trailing = try CLIRequest.parse(["run", "config.toml", "--dry-run"], in: environment)
    for request in [leading, trailing] {
      guard case .run(let configuration, let dryRun) = request else {
        return XCTFail("expected a run request, got \(request)")
      }
      XCTAssertTrue(dryRun)
      XCTAssertTrue(configuration.path.hasSuffix("config.toml"))
    }
  }

  func testHelpFlagIsAcceptedInAnyPosition() throws {
    XCTAssertEqual(try CLIRequest.parse(["run", "--help"], in: environment), .help(.run))
    XCTAssertEqual(
      try CLIRequest.parse(["run", "config.toml", "--help"], in: environment), .help(.run))
    XCTAssertEqual(try CLIRequest.parse(["check", "-h"], in: environment), .help(.check))
  }

  func testListenStillRejectsAnyArgumentOrOption() {
    XCTAssertThrowsError(try CLIRequest.parse(["listen", "extra"], in: environment))
    XCTAssertThrowsError(try CLIRequest.parse(["listen", "--verbose"], in: environment))
  }

  func testPositionalConfigPathsStillResolve() throws {
    guard case .check(let configuration) = try CLIRequest.parse(
      ["check", "my config.toml"], in: environment)
    else { return XCTFail("check should keep accepting a positional config path") }
    XCTAssertTrue(configuration.path.hasSuffix("my config.toml"))
  }

  // MARK: structured help

  func testRootHelpShowsCobraLikeSections() {
    let text = CLIHelp.text(
      for: .root,
      defaultConfigurationURL: URL(fileURLWithPath: "/tmp/default/config.toml"))

    for section in ["Name:", "Usage:", "Available Commands:", "Flags:", "Examples:"] {
      XCTAssertTrue(text.contains(section), "root help must contain \(section)")
    }
    for command in ["init", "listen", "check", "run", "service", "help", "version"] {
      XCTAssertTrue(text.contains(command), "root help must list \(command)")
    }
    XCTAssertTrue(text.contains("--version"))
    XCTAssertTrue(text.contains("--dry-run"))
  }

  func testPerCommandHelpShowsNameUsageFlagsAndExamples() {
    let defaultURL = URL(fileURLWithPath: "/tmp/default/config.toml")
    for topic in [CLIHelpTopic.initialize, .listen, .check, .run, .service] {
      let text = CLIHelp.text(for: topic, defaultConfigurationURL: defaultURL)
      for section in ["Name:", "Usage:", "Flags:", "Examples:", "Prerequisites:"] {
        XCTAssertTrue(text.contains(section), "\(topic) help must contain \(section)")
      }
      XCTAssertTrue(text.contains(defaultURL.path))
    }
  }

  func testServiceHelpListsAllActions() {
    let text = CLIHelp.text(
      for: .service,
      defaultConfigurationURL: URL(fileURLWithPath: "/tmp/default/config.toml"))
    for action in ["install", "status", "start", "stop", "restart", "uninstall"] {
      XCTAssertTrue(text.contains(action), "service help must document \(action)")
    }
  }

  func testRootHelpKeepsRecoveryAndSafetyGuidance() {
    let text = CLIHelp.text(
      for: .root,
      defaultConfigurationURL: URL(fileURLWithPath: "/tmp/default/config.toml"))
    XCTAssertTrue(text.contains("aerospace-gestures check <config.toml>"))
    XCTAssertTrue(text.contains("aerospace-gestures init"))
    XCTAssertTrue(text.contains("Private MultitouchSupport API is experimental"))
  }

  func testUnknownCommandErrorListsAvailableCommands() {
    let error = CLIArgumentError.unknownCommand("bogus")
    XCTAssertTrue(String(describing: error).contains("Available commands"))
    XCTAssertTrue(String(describing: error).contains("version"))
  }

  private static func repositoryRoot() -> URL {
    var url = URL(fileURLWithPath: #filePath)
    for _ in 0..<6 {
      url.deleteLastPathComponent()
      if FileManager.default.fileExists(atPath: url.appendingPathComponent("CHANGELOG.md").path) {
        return url
      }
    }
    fatalError("could not locate repository root containing CHANGELOG.md from \(#filePath)")
  }
}
