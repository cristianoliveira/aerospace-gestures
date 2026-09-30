import Darwin
import Foundation
import GestureCore
import GestureInfrastructure
import XCTest

final class ConfigurationReloadAdapterTests: XCTestCase {
  func testManualRunKeepsItsExplicitConfigurationPath() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let fallback = fixture.root.appendingPathComponent("manual/config.json")
    let paths = fixture.sourcePaths
    let resolver = ConfigurationReloadSourceResolver(
      nixManaged: false,
      fallbackURL: fallback,
      currentExecutableURL: fixture.executableURL,
      paths: paths,
      trustedOwnerUID: getuid())

    XCTAssertEqual(try resolver.resolve(), fallback.standardizedFileURL)
  }

  func testNixReloadReadsLatestTargetBehindStableConfigurationSymlink() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let first = try fixture.writeStoreConfiguration("old")
    try fixture.installManagedPlist()
    try fixture.pointStableConfiguration(to: first)

    let resolver = fixture.resolver(nixManaged: true)
    let adapter = ConfigurationReloadAdapter(sourceResolver: resolver) { configuration in
      guard configuration.bindings.allSatisfy({ $0.command[0] == "/bin/echo" }) else {
        throw FixtureError.rejectedConfiguration
      }
    }

    XCTAssertEqual(try adapter.load().bindings.first?.command, ["/bin/echo", "old"])

    let second = try fixture.writeStoreConfiguration("new")
    try fixture.pointStableConfiguration(to: second)

    XCTAssertEqual(try adapter.load().bindings.first?.command, ["/bin/echo", "new"])
  }

  func testInvalidManagedPlistIsRejectedWithoutFallingBack() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.installManagedPlist(label: "foreign.label")
    try fixture.pointStableConfiguration(to: fixture.writeStoreConfiguration("latest"))

    let resolver = fixture.resolver(nixManaged: true)
    let adapter = ConfigurationReloadAdapter(sourceResolver: resolver) { _ in
      XCTFail("Validation must not run when source trust fails")
    }

    XCTAssertThrowsError(try adapter.load()) { error in
      XCTAssertTrue(String(describing: error).contains("Label"))
    }
  }

  func testNixManagedPlistRequiresMarkerAndExactArguments() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.installManagedPlist(nixManagedMarker: nil)
    XCTAssertThrowsError(try fixture.resolver(nixManaged: true).resolve()) { error in
      XCTAssertTrue(String(describing: error).contains("Nix reload marker"))
    }

    try fixture.installManagedPlist(
      programArguments: [
        fixture.executableURL.path, "run", fixture.managedConfigurationURL.path, "extra",
      ])
    XCTAssertThrowsError(try fixture.resolver(nixManaged: true).resolve()) { error in
      XCTAssertTrue(String(describing: error).contains("ProgramArguments"))
    }
  }

  func testExecutableMismatchAndUntrustedStoreTargetAreRejected() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    try fixture.installManagedPlist(executablePath: "/tmp/other-aerospace-gestures")
    try fixture.pointStableConfiguration(to: fixture.writeStoreConfiguration("first"))

    XCTAssertThrowsError(try fixture.resolver(nixManaged: true).resolve()) { error in
      XCTAssertTrue(String(describing: error).contains("executable"))
    }

    try fixture.installManagedPlist()
    let writableTarget = try fixture.writeStoreConfiguration("writable", permissions: 0o644)
    try fixture.pointStableConfiguration(to: writableTarget)

    XCTAssertThrowsError(try fixture.resolver(nixManaged: true).resolve()) { error in
      XCTAssertTrue(String(describing: error).contains("store"))
    }
  }

  func testInvalidJSONPreventsAdapterValidationAndReloadCandidate() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let invalidJSON = fixture.storeDirectoryURL.appendingPathComponent(
      "invalid-aerospace-gestures.json")
    try Data("not json".utf8).write(to: invalidJSON)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o444], ofItemAtPath: invalidJSON.path)
    try fixture.installManagedPlist()
    try fixture.pointStableConfiguration(to: invalidJSON)
    let adapter = ConfigurationReloadAdapter(sourceResolver: fixture.resolver(nixManaged: true)) {
      _ in XCTFail("Invalid JSON must not reach executable validation")
    }

    XCTAssertThrowsError(try adapter.load())
  }

  func testConfigurationValidationFailurePreventsAdapterSuccess() throws {
    let fixture = try Fixture()
    defer { fixture.remove() }
    let storeConfiguration = try fixture.writeStoreConfiguration("valid")
    try fixture.installManagedPlist()
    try fixture.pointStableConfiguration(to: storeConfiguration)
    let adapter = ConfigurationReloadAdapter(sourceResolver: fixture.resolver(nixManaged: true)) {
      _ in throw FixtureError.rejectedConfiguration
    }

    XCTAssertThrowsError(try adapter.load()) { error in
      XCTAssertEqual(String(describing: error), "test validator rejected config")
    }
  }

  private enum FixtureError: Error, CustomStringConvertible {
    case rejectedConfiguration
    var description: String { "test validator rejected config" }
  }

  private final class Fixture {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let executableURL: URL
    let plistURL: URL
    let managedConfigurationURL: URL
    let storeDirectoryURL: URL

    init() throws {
      executableURL = root.appendingPathComponent("bin/aerospace-gestures")
      plistURL = root.appendingPathComponent("Library/LaunchAgents/com.aerospace-gestures.plist")
      managedConfigurationURL = root.appendingPathComponent("etc/aerospace-gestures/config.json")
      storeDirectoryURL = root.appendingPathComponent("nix/store", isDirectory: true)
      try FileManager.default.createDirectory(
        at: executableURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try FileManager.default.createDirectory(
        at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try FileManager.default.createDirectory(
        at: managedConfigurationURL.deletingLastPathComponent(), withIntermediateDirectories: true)
      try FileManager.default.createDirectory(
        at: storeDirectoryURL, withIntermediateDirectories: true)
      try Data("executable".utf8).write(to: executableURL)
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o700], ofItemAtPath: executableURL.path)
      for directory in [
        executableURL.deletingLastPathComponent(), plistURL.deletingLastPathComponent(),
        managedConfigurationURL.deletingLastPathComponent(), storeDirectoryURL,
      ] {
        try FileManager.default.setAttributes(
          [.posixPermissions: 0o755], ofItemAtPath: directory.path)
      }
    }

    var sourcePaths: ConfigurationReloadSourcePaths {
      ConfigurationReloadSourcePaths(
        launchAgentPlistURL: plistURL,
        managedConfigurationURL: managedConfigurationURL,
        storeDirectoryURL: storeDirectoryURL)
    }

    func resolver(nixManaged: Bool) -> ConfigurationReloadSourceResolver {
      ConfigurationReloadSourceResolver(
        nixManaged: nixManaged,
        fallbackURL: root.appendingPathComponent("manual/config.json"),
        currentExecutableURL: executableURL,
        paths: sourcePaths,
        trustedOwnerUID: getuid())
    }

    func installManagedPlist(
      label: String = "com.aerospace-gestures", executablePath: String? = nil,
      nixManagedMarker: String? = "1", programArguments: [String]? = nil
    ) throws {
      let arguments =
        programArguments
        ?? [executablePath ?? executableURL.path, "run", managedConfigurationURL.path]
      var properties: [String: Any] = ["Label": label, "ProgramArguments": arguments]
      if let nixManagedMarker {
        properties["EnvironmentVariables"] = [
          ConfigurationReloadSourceResolver.nixManagedEnvironmentKey: nixManagedMarker
        ]
      }
      let data = try PropertyListSerialization.data(
        fromPropertyList: properties, format: .xml, options: 0)
      if FileManager.default.fileExists(atPath: plistURL.path) {
        try FileManager.default.removeItem(at: plistURL)
      }
      try data.write(to: plistURL)
      try FileManager.default.setAttributes([.posixPermissions: 0o444], ofItemAtPath: plistURL.path)
    }

    func writeStoreConfiguration(_ argument: String, permissions: Int = 0o444) throws -> URL {
      let url = storeDirectoryURL.appendingPathComponent("test-aerospace-gestures.json")
      let data = Data(
        """
        {"bindings":[{"fingers":3,"direction":"down","command":["/bin/echo","\(argument)"]}]}
        """.utf8)
      if FileManager.default.fileExists(atPath: url.path) {
        try FileManager.default.removeItem(at: url)
      }
      try data.write(to: url)
      try FileManager.default.setAttributes(
        [.posixPermissions: permissions], ofItemAtPath: url.path)
      return url
    }

    func pointStableConfiguration(to target: URL) throws {
      if FileManager.default.fileExists(atPath: managedConfigurationURL.path) {
        try FileManager.default.removeItem(at: managedConfigurationURL)
      }
      try FileManager.default.createSymbolicLink(
        atPath: managedConfigurationURL.path, withDestinationPath: target.path)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }
  }
}
