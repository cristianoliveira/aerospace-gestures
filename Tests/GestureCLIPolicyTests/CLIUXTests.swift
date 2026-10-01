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

  func testVersionConstantMatchesTheCurrentDevelopmentLine() {
    // Independent expected value for unreleased CLI work. Before tagging, the
    // release workflow requires dropping `-dev` so the packaged binary exactly
    // matches the real tag.
    XCTAssertEqual(CLIVersion.current, "0.3.0-dev")
  }

  // MARK: help routing

  func testHelpCommandRoutesToEveryAdvertisedCommand() throws {
    let cases: [([String], CLIHelpTopic)] = [
      (["help"], .root),
      (["help", "init"], .initialize),
      (["help", "listen"], .listen),
      (["help", "check"], .check),
      (["help", "run"], .run),
      (["help", "service"], .service),
      (["help", "help"], .help),
      (["help", "version"], .version),
    ]
    for (arguments, topic) in cases {
      XCTAssertEqual(try CLIRequest.parse(arguments, in: environment), .help(topic))
    }
  }

  func testAdvertisedCommandsAndServiceActionsAcceptHelpFlags() throws {
    XCTAssertEqual(try CLIRequest.parse(["help", "--help"], in: environment), .help(.help))
    XCTAssertEqual(try CLIRequest.parse(["help", "-h"], in: environment), .help(.help))
    XCTAssertEqual(try CLIRequest.parse(["version", "--help"], in: environment), .help(.version))
    XCTAssertEqual(try CLIRequest.parse(["version", "-h"], in: environment), .help(.version))
    for action in ["install", "status", "start", "stop", "restart", "uninstall"] {
      XCTAssertEqual(
        try CLIRequest.parse(["service", action, "--help"], in: environment),
        .help(.service))
    }
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

  func testUnknownCommandErrorListsCommandsAndRootHelpOnce() {
    let description = String(describing: CLIArgumentError.unknownCommand("bogus"))
    XCTAssertTrue(description.contains("Available commands"))
    XCTAssertTrue(description.contains("version"))
    XCTAssertEqual(description.components(separatedBy: "Run aerospace-gestures --help").count, 2)
  }

  func testParseErrorsIncludeOneRelevantPerCommandHint() {
    let cases: [([String], String)] = [
      (["check", "--faster"], "aerospace-gestures check --help"),
      (["run", "--faster"], "aerospace-gestures run --help"),
      (["service", "--faster"], "aerospace-gestures service --help"),
      (["version", "--faster"], "aerospace-gestures version --help"),
      (["listen", "extra"], "aerospace-gestures listen --help"),
      (["help", "check", "extra"], "aerospace-gestures help --help"),
    ]
    for (arguments, hint) in cases {
      XCTAssertThrowsError(try CLIRequest.parse(arguments, in: environment)) { error in
        let description = String(describing: error)
        XCTAssertTrue(description.contains(hint), "missing relevant hint for \(arguments)")
        XCTAssertEqual(description.components(separatedBy: hint).count, 2)
      }
    }
  }

  func testHelpSeparatesSectionsWithBlankLines() {
    let text = CLIHelp.text(
      for: .root,
      defaultConfigurationURL: URL(fileURLWithPath: "/tmp/default/config.toml"))
    for nextHeading in ["Available Commands:", "Flags:", "Examples:"] {
      XCTAssertTrue(text.contains("\n\n\(nextHeading)"), "missing space before \(nextHeading)")
    }
  }
}
