import Foundation
import GestureCore
import GestureInfrastructure
import XCTest

@testable import GestureCLIPolicy

final class CLIConfigurationTests: XCTestCase {
  private let home = URL(fileURLWithPath: "/tmp/home with spaces", isDirectory: true)
  private let currentDirectory = URL(fileURLWithPath: "/tmp/work tree", isDirectory: true)

  func testExplicitAbsolutePathTakesPrecedenceOverExistingDefault() throws {
    let explicit = URL(fileURLWithPath: "/tmp/explicit config.toml")
    let environment = CLIEnvironment(
      values: ["XDG_CONFIG_HOME": "/tmp/xdg"], homeDirectory: home,
      currentDirectory: currentDirectory)

    XCTAssertEqual(
      try CLIRequest.parse(["check", explicit.path], in: environment),
      .check(configuration: explicit))
  }

  func testExplicitRelativePathTakesPrecedenceAndResolvesFromCurrentDirectory() throws {
    let environment = CLIEnvironment(
      values: ["XDG_CONFIG_HOME": "/xdg/config"], homeDirectory: home,
      currentDirectory: currentDirectory)

    let request = try CLIRequest.parse(
      ["run", "relative config.toml", "--dry-run"], in: environment)

    XCTAssertEqual(
      request,
      .run(
        configuration: URL(
          fileURLWithPath: "relative config.toml", relativeTo: currentDirectory
        ).standardizedFileURL,
        dryRun: true))
  }

  func testAbsoluteXDGDirectoryIsUsedForDefaultAndAllowsSpaces() throws {
    let environment = CLIEnvironment(
      values: ["XDG_CONFIG_HOME": "/tmp/config root"], homeDirectory: home,
      currentDirectory: currentDirectory)

    let request = try CLIRequest.parse(["check"], in: environment)

    XCTAssertEqual(
      request,
      .check(configuration: URL(fileURLWithPath: "/tmp/config root/aerospace-gestures/config.toml"))
    )
  }

  func testEmptyOrRelativeXDGDirectoryFallsBackToHomeConfigDirectory() throws {
    for xdgValue in ["", "relative/config"] {
      let environment = CLIEnvironment(
        values: ["XDG_CONFIG_HOME": xdgValue], homeDirectory: home,
        currentDirectory: currentDirectory)

      let request = try CLIRequest.parse(["check"], in: environment)

      XCTAssertEqual(
        request,
        .check(
          configuration: URL(
            fileURLWithPath: ".config/aerospace-gestures/config.toml", relativeTo: home
          )
          .standardizedFileURL))
    }
  }

  func testRunWithoutPathUsesDefaultAndAcceptsDryRunFlag() throws {
    let environment = CLIEnvironment(
      values: [:], homeDirectory: home, currentDirectory: currentDirectory)

    let request = try CLIRequest.parse(["run", "--dry-run"], in: environment)

    XCTAssertEqual(
      request,
      .run(
        configuration: URL(
          fileURLWithPath: ".config/aerospace-gestures/config.toml", relativeTo: home
        )
        .standardizedFileURL,
        dryRun: true))
  }

  func testSubcommandHelpIncludesDefaultPathPrerequisitesExamplesAndRecovery() throws {
    let environment = CLIEnvironment(
      values: [:], homeDirectory: home, currentDirectory: currentDirectory)
    let defaultURL = ConfigurationPath.resolve(explicitPath: nil, in: environment)

    for topic in [CLIHelpTopic.root, .initialize, .check, .run, .listen, .service] {
      let text = CLIHelp.text(for: topic, defaultConfigurationURL: defaultURL)
      XCTAssertTrue(text.contains(defaultURL.path))
      XCTAssertTrue(text.contains("Prerequisites:"))
      XCTAssertTrue(text.contains("Example:"))
      XCTAssertTrue(text.contains("aerospace-gestures init"))
      XCTAssertTrue(text.contains("aerospace-gestures check <config.toml>"))
    }
    let runHelp = CLIHelp.text(for: .run, defaultConfigurationURL: defaultURL)
    XCTAssertTrue(runHelp.contains("Reload configuration"))
    XCTAssertTrue(runHelp.contains("without restarting input"))

    let serviceHelp = CLIHelp.text(for: .service, defaultConfigurationURL: defaultURL)
    for term in ["LaunchAgent", "Library/LaunchAgents", "Input Monitoring/TCC", "/dev/null"] {
      XCTAssertTrue(serviceHelp.localizedCaseInsensitiveContains(term))
    }
  }

  func testServiceLifecycleArgumentsAreParsedWithoutStartingDevices() throws {
    let environment = CLIEnvironment(
      values: [:], homeDirectory: home, currentDirectory: currentDirectory)
    let commands: [(String, CLIServiceAction)] = [
      ("install", .install), ("status", .status), ("start", .start),
      ("stop", .stop), ("restart", .restart), ("uninstall", .uninstall),
    ]

    for (argument, action) in commands {
      XCTAssertEqual(
        try CLIRequest.parse(["service", argument], in: environment), .service(action))
    }
    XCTAssertEqual(try CLIRequest.parse(["service", "--help"], in: environment), .help(.service))
    XCTAssertThrowsError(try CLIRequest.parse(["service"], in: environment))
    XCTAssertThrowsError(try CLIRequest.parse(["service", "start", "extra"], in: environment))
    XCTAssertThrowsError(try CLIRequest.parse(["service", "reload"], in: environment))
  }

  func testSubcommandHelpAndInvalidArgumentsAreParsedWithoutStartingDevices() throws {
    let environment = CLIEnvironment(
      values: [:], homeDirectory: home, currentDirectory: currentDirectory)

    XCTAssertEqual(try CLIRequest.parse(["init", "--help"], in: environment), .help(.initialize))
    XCTAssertThrowsError(try CLIRequest.parse(["listen", "extra"], in: environment))
    XCTAssertThrowsError(try CLIRequest.parse(["check", "one", "two"], in: environment))
    XCTAssertThrowsError(try CLIRequest.parse(["unknown"], in: environment))
    XCTAssertThrowsError(
      try CLIRequest.parse(["run", "config.toml", "--unknown"], in: environment))
  }

  func testExecutableValidationUsesInjectedCheckAndDoesNotRunCommands() throws {
    let configuration = try Configuration.load(
      Data(
        """
        [[bindings]]
        fingers = 3
        direction = "down"
        command = ["/path with spaces/popup"]
        """.utf8))
    var checked: [String] = []

    try ConfigurationDecision.validateExecutables(in: configuration) { path in
      checked.append(path)
      return true
    }

    XCTAssertEqual(checked, ["/path with spaces/popup"])
  }

  func testExecutableValidationReportsMissingCommand() throws {
    let configuration = try Configuration.load(
      Data(
        """
        [[bindings]]
        fingers = 3
        direction = "down"
        command = ["/missing/popup"]
        """.utf8))

    XCTAssertThrowsError(
      try ConfigurationDecision.validateExecutables(in: configuration) { _ in false }
    ) { error in
      XCTAssertTrue(String(describing: error).contains("/missing/popup"))
    }
  }

  func testMissingExplicitPathDoesNotFallBackToExistingDefault() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let xdg = directory.appendingPathComponent("xdg", isDirectory: true)
    let defaultPath =
      xdg
      .appendingPathComponent("aerospace-gestures", isDirectory: true)
      .appendingPathComponent("config.toml")
    let explicitPath = directory.appendingPathComponent("missing config.toml")
    try FileManager.default.createDirectory(
      at: defaultPath.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data(ConfigurationFile.defaultContents.utf8).write(to: defaultPath)
    let environment = CLIEnvironment(
      values: ["XDG_CONFIG_HOME": xdg.path], homeDirectory: home,
      currentDirectory: directory)

    guard
      case .check(let resolvedPath) = try CLIRequest.parse(
        ["check", explicitPath.path], in: environment)
    else { return XCTFail("check should retain the explicit missing path") }
    XCTAssertEqual(resolvedPath, explicitPath)
    XCTAssertNoThrow(try ConfigurationFile.load(at: defaultPath))
    XCTAssertThrowsError(try ConfigurationFile.load(at: resolvedPath)) { error in
      XCTAssertTrue(String(describing: error).contains(resolvedPath.path))
    }
    XCTAssertTrue(CLIConfigurationFailure.missing(at: resolvedPath).contains(resolvedPath.path))
    XCTAssertTrue(
      CLIConfigurationFailure.missing(at: resolvedPath).contains("aerospace-gestures init"))
  }

  func testInvalidExplicitConfigurationErrorIncludesResolvedPath() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let invalidPath = directory.appendingPathComponent("bad config.toml")
    try Data("[[bindings]".utf8).write(to: invalidPath)

    XCTAssertThrowsError(try ConfigurationFile.load(at: invalidPath)) { error in
      XCTAssertTrue(
        CLIConfigurationFailure.invalid(at: invalidPath, reason: error).contains(invalidPath.path))
    }
  }

  func testInitCreatesPopupConfigurationAndRepeatedInitNeverOverwrites() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let temporaryHome = directory.appendingPathComponent("home with spaces", isDirectory: true)
    let environment = CLIEnvironment(
      values: ["XDG_CONFIG_HOME": ""], homeDirectory: temporaryHome,
      currentDirectory: directory)
    guard case .initialize(let destination) = try CLIRequest.parse(["init"], in: environment) else {
      return XCTFail("init should resolve to the temporary home config path")
    }

    try ConfigurationFile.initializeDefault(at: destination)
    let firstContents = try Data(contentsOf: destination)
    let configuration = try ConfigurationFile.load(at: destination)

    XCTAssertEqual(configuration.threshold, 0.15)
    XCTAssertEqual(configuration.bindings.map(\.gesture), [Gesture(fingers: 3, direction: .down)])
    XCTAssertEqual(configuration.bindings[0].command[0], "/usr/bin/osascript")
    XCTAssertThrowsError(try ConfigurationFile.initializeDefault(at: destination))
    XCTAssertEqual(try Data(contentsOf: destination), firstContents)
  }

  func testInitReportsParentDirectoryCreationFailureWithoutChangingBlocker() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let blocker = directory.appendingPathComponent("not a directory")
    let original = Data("preserve".utf8)
    try original.write(to: blocker)
    let destination = blocker.appendingPathComponent("config.toml")

    XCTAssertThrowsError(try ConfigurationFile.initializeDefault(at: destination)) { error in
      XCTAssertTrue(String(describing: error).contains(blocker.path))
    }
    XCTAssertEqual(try Data(contentsOf: blocker), original)
  }

  func testInitRefusesToReplaceSymlink() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let target = directory.appendingPathComponent("existing.toml")
    let destination = directory.appendingPathComponent("config.toml")
    let original = Data("keep this".utf8)
    try original.write(to: target)
    try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: target)

    XCTAssertThrowsError(try ConfigurationFile.initializeDefault(at: destination))
    XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path))
    XCTAssertEqual(
      try FileManager.default.destinationOfSymbolicLink(atPath: destination.path), target.path)
    XCTAssertEqual(try Data(contentsOf: target), original)
  }
}
