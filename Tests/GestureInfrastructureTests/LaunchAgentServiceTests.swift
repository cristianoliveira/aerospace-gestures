import Foundation
import XCTest

@testable import GestureInfrastructure

final class LaunchAgentServiceTests: XCTestCase {
  func testInstallWritesOwnedStructuredPlistAndStartsOnlyInInjectedUserDomain() throws {
    let fixture = try ServiceFixture()
    defer { fixture.remove() }

    XCTAssertEqual(try fixture.service.install(), .installed)

    let plist = try XCTUnwrap(
      PropertyListSerialization.propertyList(
        from: Data(contentsOf: fixture.paths.plistURL), options: [], format: nil)
        as? [String: Any])
    XCTAssertEqual(plist["Label"] as? String, LaunchAgentPaths.label)
    XCTAssertEqual(
      plist["ProgramArguments"] as? [String],
      [fixture.paths.executableURL.path, "run", fixture.paths.configurationURL.path])
    XCTAssertEqual(plist["WorkingDirectory"] as? String, fixture.paths.homeDirectory.path)
    XCTAssertEqual(plist["RunAtLoad"] as? Bool, true)
    let keepAlive = try XCTUnwrap(plist["KeepAlive"] as? [String: Any])
    XCTAssertEqual(keepAlive["SuccessfulExit"] as? Bool, false)
    XCTAssertEqual(plist["ThrottleInterval"] as? Int, 30)
    XCTAssertEqual(plist["StandardOutPath"] as? String, "/dev/null")
    XCTAssertEqual(plist["StandardErrorPath"] as? String, "/dev/null")
    XCTAssertEqual(
      (plist["EnvironmentVariables"] as? [String: String])?["AEROSPACE_GESTURES_MANAGED"], "1")
    XCTAssertEqual(
      fixture.runner.calls.last,
      ["bootstrap", fixture.paths.domain, fixture.paths.plistURL.path])
  }

  func testInstallKickstartsOwnedJobThatIsLoadedButNotRunning() throws {
    let fixture = try ServiceFixture()
    defer { fixture.remove() }
    XCTAssertEqual(try fixture.service.install(), .installed)
    fixture.runner.isRunning = false
    let callsBefore = fixture.runner.calls.count

    XCTAssertEqual(try fixture.service.install(), .started)

    XCTAssertTrue(fixture.runner.isRunning)
    XCTAssertEqual(fixture.runner.calls[callsBefore].first, "print")
    XCTAssertEqual(fixture.runner.calls.last?.first, "kickstart")
    XCTAssertFalse(fixture.runner.calls.contains { $0.first == "bootout" })
  }

  func testStartKickstartsOwnedJobThatIsLoadedButNotRunning() throws {
    let fixture = try ServiceFixture()
    defer { fixture.remove() }
    XCTAssertEqual(try fixture.service.install(), .installed)
    fixture.runner.isRunning = false

    XCTAssertEqual(try fixture.service.start(), .started)

    XCTAssertTrue(fixture.runner.isRunning)
    XCTAssertEqual(fixture.runner.calls.last?.first, "kickstart")
  }

  func testRepeatedInstallIsAnIdempotentNoOp() throws {
    let fixture = try ServiceFixture()
    defer { fixture.remove() }

    XCTAssertEqual(try fixture.service.install(), .installed)
    let callsAfterFirstInstall = fixture.runner.calls.count

    XCTAssertEqual(try fixture.service.install(), .alreadyInstalled)
    XCTAssertFalse(
      fixture.runner.calls.dropFirst(callsAfterFirstInstall).contains {
        $0.first == "bootstrap" || $0.first == "bootout"
      })
  }

  func testInstallRefusesForeignAndMalformedPlistsWithoutChangingThem() throws {
    for contents in [Data("not a plist".utf8), try foreignPlist()] {
      let fixture = try ServiceFixture()
      defer { fixture.remove() }
      try FileManager.default.createDirectory(
        at: fixture.paths.launchAgentsDirectory, withIntermediateDirectories: true)
      try contents.write(to: fixture.paths.plistURL)

      XCTAssertThrowsError(try fixture.service.install())
      XCTAssertEqual(try Data(contentsOf: fixture.paths.plistURL), contents)
      XCTAssertFalse(
        FileManager.default.fileExists(
          atPath: fixture.paths.operationLockURL.deletingLastPathComponent().path))
      XCTAssertTrue(fixture.runner.calls.isEmpty)
    }
  }

  func testInstallRejectsPlistSymlinkWithoutChangingTarget() throws {
    let fixture = try ServiceFixture()
    defer { fixture.remove() }
    try FileManager.default.createDirectory(
      at: fixture.paths.launchAgentsDirectory, withIntermediateDirectories: true)
    let target = fixture.root.appendingPathComponent("foreign.plist")
    let contents = try foreignPlist()
    try contents.write(to: target)
    try FileManager.default.createSymbolicLink(
      at: fixture.paths.plistURL, withDestinationURL: target)

    XCTAssertThrowsError(try fixture.service.install())
    XCTAssertEqual(try Data(contentsOf: target), contents)
    XCTAssertEqual(
      try FileManager.default.destinationOfSymbolicLink(atPath: fixture.paths.plistURL.path),
      target.path)
    XCTAssertTrue(fixture.runner.calls.isEmpty)
  }

  func testInstallValidatesBinaryAndConfigurationBeforeAnyMutation() throws {
    let fixture = try ServiceFixture()
    defer { fixture.remove() }
    try FileManager.default.removeItem(at: fixture.paths.executableURL)

    XCTAssertThrowsError(try fixture.service.install())
    XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.paths.plistURL.path))
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: fixture.paths.operationLockURL.deletingLastPathComponent().path))
    XCTAssertTrue(fixture.runner.calls.isEmpty)

    try fixture.makeExecutable()
    try FileManager.default.removeItem(at: fixture.paths.configurationURL)
    XCTAssertThrowsError(try fixture.service.install())
    XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.paths.plistURL.path))
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: fixture.paths.operationLockURL.deletingLastPathComponent().path))
    XCTAssertTrue(fixture.runner.calls.isEmpty)
  }

  func testInstallUpdateRollsBackPriorPlistAndRegistrationOnBootstrapFailure() throws {
    let fixture = try ServiceFixture()
    defer { fixture.remove() }
    XCTAssertEqual(try fixture.service.install(), .installed)
    let originalPlist = try Data(contentsOf: fixture.paths.plistURL)

    let replacementConfig = fixture.root.appendingPathComponent("new config.toml")
    try fixture.writeConfiguration(at: replacementConfig)
    let updatedPaths = LaunchAgentPaths(
      homeDirectory: fixture.paths.homeDirectory,
      executableURL: fixture.paths.executableURL,
      configurationURL: replacementConfig,
      uid: fixture.paths.uid,
      launchctlURL: fixture.paths.launchctlURL)
    let updatedService = LaunchAgentService(paths: updatedPaths, processRunner: fixture.runner)
    fixture.runner.failNextBootstrap = true

    XCTAssertThrowsError(try updatedService.install())
    XCTAssertEqual(try Data(contentsOf: fixture.paths.plistURL), originalPlist)
    XCTAssertTrue(fixture.runner.isLoaded)
    XCTAssertEqual(
      fixture.runner.calls.suffix(5),
      [
        ["print", fixture.paths.serviceTarget],
        ["bootout", fixture.paths.serviceTarget],
        ["bootstrap", fixture.paths.domain, fixture.paths.plistURL.path],
        ["print", fixture.paths.serviceTarget],
        ["bootstrap", fixture.paths.domain, fixture.paths.plistURL.path],
      ])
  }

  func testFailedFirstInstallRemovesOnlyItsNewPlist() throws {
    let fixture = try ServiceFixture()
    defer { fixture.remove() }
    fixture.runner.failNextBootstrap = true

    XCTAssertThrowsError(try fixture.service.install())
    XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.paths.plistURL.path))
    XCTAssertFalse(fixture.runner.isLoaded)
  }

  func testStartStopAndUninstallAreIdempotentAndPreserveUserData() throws {
    let fixture = try ServiceFixture()
    defer { fixture.remove() }
    XCTAssertEqual(try fixture.service.install(), .installed)
    let config = try Data(contentsOf: fixture.paths.configurationURL)
    let binary = try Data(contentsOf: fixture.paths.executableURL)

    XCTAssertEqual(try fixture.service.stop(), .stopped)
    XCTAssertEqual(try fixture.service.stop(), .alreadyStopped)
    XCTAssertTrue(FileManager.default.fileExists(atPath: fixture.paths.plistURL.path))
    XCTAssertEqual(try fixture.service.start(), .started)
    XCTAssertEqual(try fixture.service.start(), .alreadyRunning)
    XCTAssertEqual(try fixture.service.uninstall(), .uninstalled)
    XCTAssertEqual(try fixture.service.uninstall(), .notInstalled)

    XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.paths.plistURL.path))
    XCTAssertEqual(try Data(contentsOf: fixture.paths.configurationURL), config)
    XCTAssertEqual(try Data(contentsOf: fixture.paths.executableURL), binary)
    XCTAssertFalse(fixture.runner.isLoaded)
  }

  func testUninstallBootoutFailurePreservesOwnedPlistAndLoadedJob() throws {
    let fixture = try ServiceFixture()
    defer { fixture.remove() }
    XCTAssertEqual(try fixture.service.install(), .installed)
    let plistBefore = try Data(contentsOf: fixture.paths.plistURL)
    fixture.runner.failNextBootout = true

    XCTAssertThrowsError(try fixture.service.uninstall())

    XCTAssertEqual(try Data(contentsOf: fixture.paths.plistURL), plistBefore)
    XCTAssertTrue(fixture.runner.isLoaded)
  }

  func testUpdateReportsRollbackFailureAndRestoresPriorPlistBytes() throws {
    let fixture = try ServiceFixture()
    defer { fixture.remove() }
    XCTAssertEqual(try fixture.service.install(), .installed)
    let oldPlist = try Data(contentsOf: fixture.paths.plistURL)
    let newConfigurationURL = fixture.paths.homeDirectory
      .appendingPathComponent(".config/alternate.toml")
    try fixture.writeConfiguration(at: newConfigurationURL)
    let updatedPaths = LaunchAgentPaths(
      homeDirectory: fixture.paths.homeDirectory,
      executableURL: fixture.paths.executableURL,
      configurationURL: newConfigurationURL,
      uid: fixture.paths.uid)
    let updater = LaunchAgentService(paths: updatedPaths, processRunner: fixture.runner)
    fixture.runner.bootstrapFailuresRemaining = 2

    XCTAssertThrowsError(try updater.install()) { error in
      XCTAssertTrue(String(describing: error).contains("rollback was incomplete"))
    }

    XCTAssertEqual(try Data(contentsOf: fixture.paths.plistURL), oldPlist)
    XCTAssertFalse(fixture.runner.isLoaded)
  }

  func testStopBootoutFailurePreservesOwnedPlistAndLoadedJob() throws {
    let fixture = try ServiceFixture()
    defer { fixture.remove() }
    XCTAssertEqual(try fixture.service.install(), .installed)
    let plistBefore = try Data(contentsOf: fixture.paths.plistURL)
    fixture.runner.failNextBootout = true

    XCTAssertThrowsError(try fixture.service.stop())

    XCTAssertEqual(try Data(contentsOf: fixture.paths.plistURL), plistBefore)
    XCTAssertTrue(fixture.runner.isLoaded)
  }

  func testStartValidatesCapturedConfigBeforeBootstrap() throws {
    let fixture = try ServiceFixture()
    defer { fixture.remove() }
    XCTAssertEqual(try fixture.service.install(), .installed)
    XCTAssertEqual(try fixture.service.stop(), .stopped)
    try FileManager.default.removeItem(at: fixture.paths.configurationURL)
    let callsBeforeStart = fixture.runner.calls

    XCTAssertThrowsError(try fixture.service.start())
    XCTAssertEqual(fixture.runner.calls, callsBeforeStart)
    XCTAssertFalse(fixture.runner.isLoaded)
  }

  func testRestartValidatesConfigBeforeStoppingAndRollsBackAfterBootstrapFailure() throws {
    let fixture = try ServiceFixture()
    defer { fixture.remove() }
    XCTAssertEqual(try fixture.service.install(), .installed)

    try Data("invalid".utf8).write(to: fixture.paths.configurationURL)
    let callsBeforeValidation = fixture.runner.calls
    XCTAssertThrowsError(try fixture.service.restart())
    XCTAssertEqual(fixture.runner.calls, callsBeforeValidation)
    XCTAssertTrue(fixture.runner.isLoaded)

    try fixture.writeConfiguration(at: fixture.paths.configurationURL)
    fixture.runner.failNextBootstrap = true
    XCTAssertThrowsError(try fixture.service.restart())
    XCTAssertTrue(fixture.runner.isLoaded)
    XCTAssertEqual(try Data(contentsOf: fixture.paths.plistURL), fixture.runner.bootstrappedPlist)
  }

  func testStatusSeparatesInstalledLoadedRunningAndUnverifiedInput() throws {
    let fixture = try ServiceFixture()
    defer { fixture.remove() }

    let absent = try fixture.service.status()
    XCTAssertEqual(absent.installation, .absent)
    XCTAssertEqual(absent.launchd, .notLoaded)

    XCTAssertEqual(try fixture.service.install(), .installed)
    let running = try fixture.service.status()
    XCTAssertEqual(running.installation, .owned)
    XCTAssertEqual(
      running.launchd,
      .running(pid: 4321, lastExitCode: nil, plistPath: fixture.paths.plistURL.standardizedFileURL))
    XCTAssertTrue(running.description.contains(fixture.paths.configurationURL.path))
    XCTAssertTrue(running.description.contains("stdout/stderr discarded (/dev/null"))
    XCTAssertTrue(running.description.contains("Last startup diagnostic: none"))
    XCTAssertTrue(running.description.contains("Trackpad responsiveness: unverified"))

    XCTAssertEqual(try fixture.service.stop(), .stopped)
    let stopped = try fixture.service.status()
    XCTAssertEqual(stopped.installation, .owned)
    XCTAssertEqual(stopped.launchd, .notLoaded)
  }

  func testRestartUsesConfigurationPathCapturedAtInstall() throws {
    let fixture = try ServiceFixture()
    defer { fixture.remove() }
    XCTAssertEqual(try fixture.service.install(), .installed)
    let alternateConfig = fixture.root.appendingPathComponent("changed default.toml")
    try Data("invalid config".utf8).write(to: alternateConfig)
    let changedDefaultPaths = LaunchAgentPaths(
      homeDirectory: fixture.paths.homeDirectory,
      executableURL: fixture.paths.executableURL,
      configurationURL: alternateConfig,
      uid: fixture.paths.uid,
      launchctlURL: fixture.paths.launchctlURL)
    let service = LaunchAgentService(paths: changedDefaultPaths, processRunner: fixture.runner)

    XCTAssertEqual(try service.restart(), .restarted)

    let plist = try XCTUnwrap(
      PropertyListSerialization.propertyList(
        from: Data(contentsOf: fixture.paths.plistURL), options: [], format: nil)
        as? [String: Any])
    XCTAssertEqual(
      (plist["ProgramArguments"] as? [String])?.last, fixture.paths.configurationURL.path)
    XCTAssertNotEqual((plist["ProgramArguments"] as? [String])?.last, alternateConfig.path)
  }

  func testStatusReportsLastExitAndSanitizedStartupDiagnostic() throws {
    let fixture = try ServiceFixture()
    defer { fixture.remove() }
    XCTAssertEqual(try fixture.service.install(), .installed)
    fixture.runner.isRunning = false
    fixture.runner.lastExitCode = 1
    try StartupDiagnosticStore(
      fileURL: fixture.paths.startupDiagnosticURL, rootURL: fixture.paths.homeDirectory
    )
    .record(.inputInitializationFailed)

    let status = try fixture.service.status()

    XCTAssertEqual(
      status.launchd,
      .loaded(
        state: "waiting", pid: nil, lastExitCode: 1,
        plistPath: fixture.paths.plistURL.standardizedFileURL))
    XCTAssertTrue(status.description.contains("last exit status: 1"))
    XCTAssertEqual(status.startupDiagnostic, .recorded(.inputInitializationFailed))
    XCTAssertTrue(status.description.contains("input initialization failed (details withheld)"))
    XCTAssertFalse(status.description.contains("secret"))
  }

  func testStatusDistinguishesUnavailableDiagnosticFromNoRecord() throws {
    let fixture = try ServiceFixture()
    defer { fixture.remove() }
    XCTAssertEqual(try fixture.service.install(), .installed)
    try Data("unrecognized".utf8).write(to: fixture.paths.startupDiagnosticURL)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600], ofItemAtPath: fixture.paths.startupDiagnosticURL.path)

    let status = try fixture.service.status()

    XCTAssertEqual(status.startupDiagnostic, .unavailable)
    XCTAssertTrue(status.description.contains("Last startup diagnostic: unavailable"))
  }

  func testStatusReportsUnavailableForUntrustedDiagnosticDirectory() throws {
    let fixture = try ServiceFixture()
    defer { fixture.remove() }
    XCTAssertEqual(try fixture.service.install(), .installed)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o777],
      ofItemAtPath: fixture.paths.startupDiagnosticURL.deletingLastPathComponent().path)

    let status = try fixture.service.status()

    XCTAssertEqual(status.startupDiagnostic, .unavailable)
  }

  func testStatusReportsUnownedLoadedRegistrationWithoutCallingItInstalled() throws {
    let fixture = try ServiceFixture()
    defer { fixture.remove() }
    fixture.runner.isLoaded = true
    fixture.runner.isRunning = true

    let status = try fixture.service.status()

    XCTAssertEqual(status.installation, .absent)
    XCTAssertEqual(status.launchd, .running(pid: 4321, lastExitCode: nil, plistPath: nil))
    XCTAssertTrue(status.description.contains("without a verified owned plist"))
  }

  func testStatusReportsForeignPlistAndUnknownLaunchctlFailureHonestly() throws {
    let fixture = try ServiceFixture()
    defer { fixture.remove() }
    try FileManager.default.createDirectory(
      at: fixture.paths.launchAgentsDirectory, withIntermediateDirectories: true)
    try foreignPlist().write(to: fixture.paths.plistURL)
    fixture.runner.printFailure = .init(status: 1, stdout: "", stderr: "permission denied")

    let status = try fixture.service.status()
    XCTAssertEqual(status.installation, .foreign)
    guard case .unknown(let reason) = status.launchd else {
      return XCTFail("unexpected launchd state: \(status.launchd)")
    }
    XCTAssertTrue(reason.contains("permission denied"))
    XCTAssertTrue(status.description.contains("responsiveness: unverified"))
  }

  func testLifecycleOperationLockSerializesConcurrentMutations() throws {
    let fixture = try ServiceFixture()
    defer { fixture.remove() }
    let lock = try InstanceLock.acquire(
      at: fixture.paths.operationLockURL, under: fixture.paths.homeDirectory)
    let callsBefore = fixture.runner.calls

    XCTAssertThrowsError(try fixture.service.install())

    XCTAssertEqual(fixture.runner.calls, callsBefore)
    lock.release()
    XCTAssertEqual(try fixture.service.install(), .installed)
  }

  func testLockConflictPreventsStartWithoutBootstrapping() throws {
    let fixture = try ServiceFixture()
    defer { fixture.remove() }
    XCTAssertEqual(try fixture.service.install(), .installed)
    XCTAssertEqual(try fixture.service.stop(), .stopped)
    let lock = try InstanceLock.acquire(
      at: fixture.paths.instanceLockURL, under: fixture.paths.homeDirectory)

    XCTAssertThrowsError(try fixture.service.start())
    XCTAssertFalse(fixture.runner.isLoaded)
    XCTAssertEqual(fixture.runner.calls.last, ["print", fixture.paths.serviceTarget])
    withExtendedLifetime(lock) {}
  }

  func testStopRefusesLoadedJobFromDifferentPlistPath() throws {
    let fixture = try ServiceFixture()
    defer { fixture.remove() }
    XCTAssertEqual(try fixture.service.install(), .installed)
    let plistBefore = try Data(contentsOf: fixture.paths.plistURL)
    fixture.runner.loadedPlistURL = URL(fileURLWithPath: "/tmp/foreign.plist")
    XCTAssertTrue(
      try fixture.service.status().description.contains("does not point to the managed plist"))

    XCTAssertThrowsError(try fixture.service.stop())

    XCTAssertFalse(fixture.runner.calls.contains { $0.first == "bootout" })
    XCTAssertTrue(fixture.runner.isLoaded)
    XCTAssertEqual(try Data(contentsOf: fixture.paths.plistURL), plistBefore)
  }

  func testUninstallRefusesPlistBeneathGroupOrWorldWritableAncestor() throws {
    for component in ["home", "Library", "LaunchAgents"] {
      let fixture = try ServiceFixture()
      defer { fixture.remove() }
      XCTAssertEqual(try fixture.service.install(), .installed)
      let original = try Data(contentsOf: fixture.paths.plistURL)
      let unsafeDirectory: URL
      switch component {
      case "home": unsafeDirectory = fixture.paths.homeDirectory
      case "Library":
        unsafeDirectory = fixture.paths.homeDirectory.appendingPathComponent("Library")
      default: unsafeDirectory = fixture.paths.launchAgentsDirectory
      }
      try FileManager.default.setAttributes(
        [.posixPermissions: 0o777], ofItemAtPath: unsafeDirectory.path)
      let callsBefore = fixture.runner.calls

      XCTAssertThrowsError(try fixture.service.uninstall(), component)

      XCTAssertEqual(try Data(contentsOf: fixture.paths.plistURL), original, component)
      XCTAssertEqual(fixture.runner.calls, callsBefore, component)
      let attributes = try FileManager.default.attributesOfItem(atPath: unsafeDirectory.path)
      XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o777, component)
    }
  }

  func testUninstallRefusesAnOwnedLookingPlistWithUnexpectedBehavior() throws {
    let fixture = try ServiceFixture()
    defer { fixture.remove() }
    try FileManager.default.createDirectory(
      at: fixture.paths.launchAgentsDirectory, withIntermediateDirectories: true)
    let unexpected = try PropertyListSerialization.data(
      fromPropertyList: [
        "Label": LaunchAgentPaths.label,
        "ProgramArguments": [
          fixture.paths.executableURL.path, "run", fixture.paths.configurationURL.path,
        ],
        "WorkingDirectory": fixture.paths.homeDirectory.path,
        "RunAtLoad": true,
        "KeepAlive": ["SuccessfulExit": false],
        "ThrottleInterval": 30,
        "StandardOutPath": "/dev/null",
        "StandardErrorPath": "/dev/null",
        "EnvironmentVariables": ["AEROSPACE_GESTURES_MANAGED": "1"],
        "MachServices": ["unexpected": true],
      ], format: .xml, options: 0)
    try unexpected.write(to: fixture.paths.plistURL)

    XCTAssertThrowsError(try fixture.service.uninstall())
    XCTAssertEqual(try Data(contentsOf: fixture.paths.plistURL), unexpected)
    XCTAssertTrue(fixture.runner.calls.isEmpty)
  }

  func testUninstallRefusesPlistOwnedByAnotherFilesystemUID() throws {
    let fixture = try ServiceFixture()
    defer { fixture.remove() }
    XCTAssertEqual(try fixture.service.install(), .installed)
    let original = try Data(contentsOf: fixture.paths.plistURL)
    let wrongOwnerPaths = LaunchAgentPaths(
      homeDirectory: fixture.paths.homeDirectory,
      executableURL: fixture.paths.executableURL,
      configurationURL: fixture.paths.configurationURL,
      uid: fixture.paths.uid,
      filesystemUID: fixture.paths.filesystemUID + 1,
      launchctlURL: fixture.paths.launchctlURL)
    let wrongOwnerService = LaunchAgentService(
      paths: wrongOwnerPaths, processRunner: fixture.runner)
    let callsBefore = fixture.runner.calls

    XCTAssertThrowsError(try wrongOwnerService.uninstall())

    XCTAssertEqual(try Data(contentsOf: fixture.paths.plistURL), original)
    XCTAssertEqual(fixture.runner.calls, callsBefore)
  }

  func testUninstallRefusesGroupOrWorldWritablePlist() throws {
    let fixture = try ServiceFixture()
    defer { fixture.remove() }
    XCTAssertEqual(try fixture.service.install(), .installed)
    let original = try Data(contentsOf: fixture.paths.plistURL)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o666], ofItemAtPath: fixture.paths.plistURL.path)
    let callsBefore = fixture.runner.calls

    XCTAssertThrowsError(try fixture.service.uninstall())

    XCTAssertEqual(try Data(contentsOf: fixture.paths.plistURL), original)
    XCTAssertEqual(fixture.runner.calls, callsBefore)
    let attributes = try FileManager.default.attributesOfItem(atPath: fixture.paths.plistURL.path)
    XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o666)
  }

  func testPlistOwnershipRequiresMarkerAndExpectedExecutable() throws {
    let fixture = try ServiceFixture()
    defer { fixture.remove() }
    try FileManager.default.createDirectory(
      at: fixture.paths.launchAgentsDirectory, withIntermediateDirectories: true)
    let foreignExecutablePlist = try PropertyListSerialization.data(
      fromPropertyList: [
        "Label": LaunchAgentPaths.label,
        "EnvironmentVariables": ["AEROSPACE_GESTURES_MANAGED": "1"],
        "ProgramArguments": ["/tmp/other-listener", "run", fixture.paths.configurationURL.path],
      ], format: .xml, options: 0)
    try foreignExecutablePlist.write(to: fixture.paths.plistURL)

    XCTAssertThrowsError(try fixture.service.uninstall())
    XCTAssertEqual(try Data(contentsOf: fixture.paths.plistURL), foreignExecutablePlist)
    XCTAssertTrue(fixture.runner.calls.isEmpty)
  }
}

private func foreignPlist() throws -> Data {
  try PropertyListSerialization.data(
    fromPropertyList: ["Label": "com.other.application", "ProgramArguments": ["/bin/true"]],
    format: .xml, options: 0)
}

private final class ServiceFixture {
  let root: URL
  let paths: LaunchAgentPaths
  let runner = FakeLaunchctlRunner()
  lazy var service = LaunchAgentService(paths: paths, processRunner: runner)

  init() throws {
    root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let home = root.appendingPathComponent("home with spaces", isDirectory: true)
    try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
    let executable = home.appendingPathComponent(".local/bin/aerospace-gestures")
    try FileManager.default.createDirectory(
      at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
    let config = home.appendingPathComponent(".config/xdg root/config.toml")
    paths = LaunchAgentPaths(
      homeDirectory: home, executableURL: executable, configurationURL: config, uid: 2403,
      launchctlURL: URL(fileURLWithPath: "/tmp/fake launchctl"))
    try writeConfiguration(at: config)
    try makeExecutable()
  }

  func makeExecutable() throws {
    let script = Data("#!/bin/sh\nexit 0\n".utf8)
    try FileManager.default.createDirectory(
      at: paths.executableURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try script.write(to: paths.executableURL)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755], ofItemAtPath: paths.executableURL.path)
  }

  func writeConfiguration(at url: URL) throws {
    let parent = url.deletingLastPathComponent()
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    let contents = """
      [[bindings]]
      fingers = 3
      direction = "down"
      command = ["/usr/bin/true"]
      """
    try Data(contents.utf8).write(to: url)
  }

  func remove() { try? FileManager.default.removeItem(at: root) }
}

private final class FakeLaunchctlRunner: ExternalProcessRunning {
  struct Failure {
    let status: Int32
    let stdout: String
    let stderr: String
  }

  var calls: [[String]] = []
  var isLoaded = false
  var isRunning = false
  var lastExitCode: Int32?
  var failNextBootstrap = false
  var bootstrapFailuresRemaining = 0
  var failNextBootout = false
  var printFailure: Failure?
  var bootstrappedPlist = Data()
  var loadedPlistURL: URL?

  func run(executable: URL, arguments: [String]) throws -> ExternalProcessResult {
    calls.append(arguments)
    switch arguments.first {
    case "print":
      if let printFailure {
        return ExternalProcessResult(
          status: printFailure.status, stdout: printFailure.stdout, stderr: printFailure.stderr)
      }
      guard isLoaded else {
        return ExternalProcessResult(
          status: 113, stdout: "", stderr: "Could not find service \"\(arguments[1])\"")
      }
      let processFields = isRunning ? "state = running\npid = 4321\n" : "state = waiting\n"
      let exitCode = lastExitCode.map { String($0) } ?? "(never exited)"
      return ExternalProcessResult(
        status: 0,
        stdout:
          "\(processFields)last exit code = \(exitCode)\npath = \(loadedPlistURL?.path ?? "")\n",
        stderr: "")
    case "bootstrap":
      if failNextBootstrap || bootstrapFailuresRemaining > 0 {
        failNextBootstrap = false
        if bootstrapFailuresRemaining > 0 { bootstrapFailuresRemaining -= 1 }
        return ExternalProcessResult(status: 5, stdout: "", stderr: "injected bootstrap failure")
      }
      guard !isLoaded else {
        return ExternalProcessResult(
          status: 113, stdout: "", stderr: "service already bootstrapped")
      }
      let plistURL = URL(fileURLWithPath: arguments[2])
      loadedPlistURL = plistURL
      bootstrappedPlist = try Data(contentsOf: plistURL)
      isLoaded = true
      isRunning = true
      return ExternalProcessResult(status: 0, stdout: "", stderr: "")
    case "kickstart":
      guard isLoaded else {
        return ExternalProcessResult(status: 113, stdout: "", stderr: "service is not loaded")
      }
      isRunning = true
      return ExternalProcessResult(status: 0, stdout: "", stderr: "")
    case "bootout":
      if failNextBootout {
        failNextBootout = false
        return ExternalProcessResult(status: 5, stdout: "", stderr: "injected bootout failure")
      }
      guard isLoaded else {
        return ExternalProcessResult(
          status: 113, stdout: "", stderr: "Could not find service \"\(arguments[1])\"")
      }
      isLoaded = false
      isRunning = false
      loadedPlistURL = nil
      return ExternalProcessResult(status: 0, stdout: "", stderr: "")
    default:
      return ExternalProcessResult(status: 64, stdout: "", stderr: "unknown fake command")
    }
  }
}
