import GestureCore
import XCTest

@testable import GestureCLIPolicy

final class CLIUXTests: XCTestCase {
  private let environment = CLIEnvironment(
    values: [:],
    homeDirectory: URL(fileURLWithPath: "/tmp/home", isDirectory: true),
    currentDirectory: URL(fileURLWithPath: "/tmp/work tree", isDirectory: true))

  // MARK: version

  func testVersionFlagsAndCommandParseToVersionRequest() throws {
    XCTAssertEqual(try CLIRequest.parse(["--version"], in: environment), .version)
    XCTAssertEqual(try CLIRequest.parse(["-v"], in: environment), .version)
    XCTAssertEqual(try CLIRequest.parse(["version"], in: environment), .version)
  }

  func testVersionConstantMatchesTheCurrentDevelopmentLine() {
    // Independent release expectation; the workflow also checks the packaged
    // binary's version against the pushed tag.
    XCTAssertEqual(CLIVersion.current, "0.4.0")
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

  func testHelpWithUnknownTopicUsesFocusedHelpTopic() {
    assertParseError(["help", "bogus"], topic: .help)
  }

  func testHelpRejectsExtraArgumentsWithFocusedHelpTopic() {
    assertParseError(["help", "check", "extra"], topic: .help)
  }

  func testRootAndCommandsWithOptionalOperandsRemainValid() throws {
    let defaultConfiguration = ConfigurationPath.resolve(explicitPath: nil, in: environment)

    XCTAssertEqual(try CLIRequest.parse([], in: environment), .help(.root))
    XCTAssertEqual(
      try CLIRequest.parse(["init"], in: environment),
      .initialize(configuration: defaultConfiguration))
    XCTAssertEqual(try CLIRequest.parse(["listen", "start"], in: environment), .listen)
    XCTAssertEqual(try CLIRequest.parse(["help"], in: environment), .help(.root))
    XCTAssertEqual(try CLIRequest.parse(["version"], in: environment), .version)
  }

  // MARK: options are never mistaken for a config path

  func testUnknownOptionIsRejectedInsteadOfBecomingAConfigPath() {
    for arguments in [
      ["check", "--dry-run"], ["init", "-x"], ["run", "--dri"], ["service", "--quiet"],
    ] {
      XCTAssertThrowsError(try CLIRequest.parse(arguments, in: environment)) { error in
        XCTAssertTrue(
          String(describing: error).contains("Unknown option"),
          "expected an unknown-option hint for \(arguments), got: \(error)")
      }
    }
  }

  func testCommandContractsRejectMissingAndExtraOperandsWithFocusedHelp() {
    let violations: [([String], CLIHelpTopic)] = [
      (["check"], .check),
      (["check", "one.toml", "two.toml"], .check),
      (["run"], .run),
      (["run", "--dry-run"], .run),
      (["run", "one.toml", "two.toml"], .run),
      (["service"], .service),
      (["service", "start", "extra"], .service),
      (["listen"], .listen),
      (["listen", "stop"], .listen),
      (["init", "one.toml", "two.toml"], .initialize),
      (["help", "check", "extra"], .help),
      (["version", "extra"], .version),
    ]

    for (arguments, topic) in violations {
      assertParseError(arguments, topic: topic)
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

  func testHelpFlagIsAcceptedInAnyPositionAndSkipsOperandValidation() throws {
    XCTAssertEqual(try CLIRequest.parse(["run", "--help"], in: environment), .help(.run))
    XCTAssertEqual(
      try CLIRequest.parse(["run", "config.toml", "extra", "--help"], in: environment),
      .help(.run))
    XCTAssertEqual(
      try CLIRequest.parse(["check", "one", "two", "-h"], in: environment), .help(.check))
    XCTAssertEqual(
      try CLIRequest.parse(["service", "nope", "extra", "--help"], in: environment),
      .help(.service))
  }

  func testListenRequiresStartActionAndRejectsUnknownActions() throws {
    assertParseError(["listen"], topic: .listen)
    assertParseError(["listen", "stop"], topic: .listen)
    XCTAssertThrowsError(try CLIRequest.parse(["listen", "--verbose"], in: environment))
    XCTAssertEqual(try CLIRequest.parse(["listen", "start"], in: environment), .listen)
    XCTAssertEqual(try CLIRequest.parse(["listen", "--help"], in: environment), .help(.listen))
    XCTAssertEqual(
      try CLIRequest.parse(["listen", "start", "-h"], in: environment), .help(.listen))
  }

  func testPositionalConfigPathsStillResolve() throws {
    guard
      case .check(let configuration) = try CLIRequest.parse(
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
    XCTAssertTrue(text.contains("-h, --help"))
    XCTAssertTrue(text.contains("-v, --version"))
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

    let checkHelp = CLIHelp.text(for: .check, defaultConfigurationURL: defaultURL)
    XCTAssertTrue(checkHelp.contains("Usage: aerospace-gestures check <config.toml>"))
    let runHelp = CLIHelp.text(for: .run, defaultConfigurationURL: defaultURL)
    XCTAssertTrue(runHelp.contains("Usage: aerospace-gestures run <config.toml> [--dry-run]"))
    XCTAssertTrue(runHelp.contains("run /path/to/config.toml --dry-run"))
    let listenHelp = CLIHelp.text(for: .listen, defaultConfigurationURL: defaultURL)
    XCTAssertTrue(listenHelp.contains("Usage: aerospace-gestures listen <start>"))
    XCTAssertTrue(listenHelp.contains("listen start"))
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

  func testUnknownRootCommandsUseRootHelpTopic() {
    assertParseError(["bogus"], topic: .root)
  }

  func testVersionShortFlagRemainsInvalidAfterSubcommands() {
    assertParseError(["check", "-v"], topic: .check)
    assertParseError(["service", "-v"], topic: .service)
  }

  func testKnownCommandParseErrorsCarryFocusedHelpTopic() {
    let cases: [([String], CLIHelpTopic)] = [
      (["init", "--faster"], .initialize),
      (["check", "--faster"], .check),
      (["run", "--faster"], .run),
      (["service", "nope"], .service),
      (["version", "--faster"], .version),
      (["listen", "extra"], .listen),
      (["help", "check", "extra"], .help),
    ]
    for (arguments, topic) in cases {
      assertParseError(arguments, topic: topic)
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

  private func assertParseError(
    _ arguments: [String], topic expectedTopic: CLIHelpTopic,
    file: StaticString = #filePath, line: UInt = #line
  ) {
    XCTAssertThrowsError(try CLIRequest.parse(arguments, in: environment), file: file, line: line) {
      error in
      guard let error = error as? CLIArgumentError else {
        return XCTFail("expected CLIArgumentError, got \(error)", file: file, line: line)
      }
      XCTAssertEqual(error.topic, expectedTopic, file: file, line: line)
    }
  }
}
