import Darwin
import Foundation
import GestureCore

public struct LaunchAgentPaths {
  public static let label = "com.aerospace-gestures"

  public let homeDirectory: URL
  public let executableURL: URL
  public let configurationURL: URL
  public let uid: UInt32
  public let filesystemUID: UInt32
  public let launchctlURL: URL

  public init(
    homeDirectory: URL,
    executableURL: URL,
    configurationURL: URL,
    uid: UInt32,
    filesystemUID: UInt32 = getuid(),
    launchctlURL: URL = URL(fileURLWithPath: "/bin/launchctl")
  ) {
    self.homeDirectory = homeDirectory.standardizedFileURL
    self.executableURL = executableURL.standardizedFileURL
    self.configurationURL = configurationURL.standardizedFileURL
    self.uid = uid
    self.filesystemUID = filesystemUID
    self.launchctlURL = launchctlURL.standardizedFileURL
  }

  public var domain: String { "gui/\(uid)" }
  public var serviceTarget: String { "\(domain)/\(Self.label)" }
  public var launchAgentsDirectory: URL {
    homeDirectory.appendingPathComponent("Library/LaunchAgents", isDirectory: true)
  }
  public var plistURL: URL {
    launchAgentsDirectory.appendingPathComponent("\(Self.label).plist")
  }
  public var instanceLockURL: URL {
    homeDirectory
      .appendingPathComponent("Library/Application Support/aerospace-gestures", isDirectory: true)
      .appendingPathComponent("listener.lock")
  }
  public var operationLockURL: URL {
    homeDirectory
      .appendingPathComponent("Library/Application Support/aerospace-gestures", isDirectory: true)
      .appendingPathComponent("service-operation.lock")
  }
}

public struct ExternalProcessResult: Equatable {
  public let status: Int32
  public let stdout: String
  public let stderr: String

  public init(status: Int32, stdout: String, stderr: String) {
    self.status = status
    self.stdout = stdout
    self.stderr = stderr
  }
}

public protocol ExternalProcessRunning {
  func run(executable: URL, arguments: [String]) throws -> ExternalProcessResult
}

public struct SystemExternalProcessRunner: ExternalProcessRunning {
  public init() {}

  public func run(executable: URL, arguments: [String]) throws -> ExternalProcessResult {
    let process = Process()
    process.executableURL = executable
    process.arguments = arguments
    let output = Pipe()
    let error = Pipe()
    process.standardOutput = output
    process.standardError = error
    try process.run()

    let outputGroup = DispatchGroup()
    var outputData = Data()
    var errorData = Data()
    outputGroup.enter()
    DispatchQueue.global().async {
      outputData = output.fileHandleForReading.readDataToEndOfFile()
      outputGroup.leave()
    }
    outputGroup.enter()
    DispatchQueue.global().async {
      errorData = error.fileHandleForReading.readDataToEndOfFile()
      outputGroup.leave()
    }
    process.waitUntilExit()
    outputGroup.wait()
    return ExternalProcessResult(
      status: process.terminationStatus,
      stdout: String(decoding: outputData, as: UTF8.self),
      stderr: String(decoding: errorData, as: UTF8.self))
  }
}

public enum ServiceOperationResult: Equatable {
  case installed
  case updated
  case alreadyInstalled
  case started
  case alreadyRunning
  case stopped
  case alreadyStopped
  case restarted
  case uninstalled
  case notInstalled
}

public enum ServiceInstallationState: Equatable {
  case absent
  case owned
  case foreign
}

public enum ServiceLaunchState: Equatable {
  case notLoaded
  case running(pid: Int32?, lastExitCode: Int32?, plistPath: URL?)
  case loaded(state: String, pid: Int32?, lastExitCode: Int32?, plistPath: URL?)
  case unknown(String)
}

public struct ServiceStatus: Equatable, CustomStringConvertible {
  public let installation: ServiceInstallationState
  public let launchd: ServiceLaunchState
  public let configurationURL: URL
  public let managedPlistURL: URL

  public init(
    installation: ServiceInstallationState,
    launchd: ServiceLaunchState,
    configurationURL: URL,
    managedPlistURL: URL
  ) {
    self.installation = installation
    self.launchd = launchd
    self.configurationURL = configurationURL
    self.managedPlistURL = managedPlistURL
  }

  public var description: String {
    let installationDescription: String
    switch installation {
    case .absent: installationDescription = "not installed"
    case .owned: installationDescription = "installed (owned plist)"
    case .foreign: installationDescription = "unmanaged or malformed plist (left untouched)"
    }

    let launchdDescription: String
    switch launchd {
    case .notLoaded:
      launchdDescription = "not loaded"
    case .running(let pid, let lastExitCode, let plistPath):
      launchdDescription =
        "running\(pid.map { " (PID \($0))" } ?? "")\(exitDescription(lastExitCode))"
        + (plistPath.map { "; plist: \($0.path)" } ?? "")
    case .loaded(let state, let pid, let lastExitCode, let plistPath):
      launchdDescription =
        "loaded, state: \(state)\(pid.map { " (PID \($0))" } ?? "")\(exitDescription(lastExitCode))"
        + (plistPath.map { "; plist: \($0.path)" } ?? "")
    case .unknown(let reason):
      launchdDescription = "unknown (\(reason))"
    }

    let ownershipWarning: String
    switch (installation, launchd) {
    case (.absent, .running), (.absent, .loaded), (.foreign, .running), (.foreign, .loaded):
      ownershipWarning = "\nWarning: launchd has an entry without a verified owned plist; no mutation attempted."
    case (.owned, .running(_, _, let path)) where !pointsToManagedPlist(path),
      (.owned, .loaded(_, _, _, let path)) where !pointsToManagedPlist(path):
      ownershipWarning = "\nWarning: loaded job does not point to the managed plist; no mutation attempted."
    default:
      ownershipWarning = ""
    }

    return """
      Installation: \(installationDescription)
      LaunchAgent: \(launchdDescription)\(ownershipWarning)
      Managed plist: \(managedPlistURL.path)
      Configuration: \(configurationURL.path)
      Logs: persistent logging disabled (stdout/stderr: /dev/null; retained bytes: 0)
      Trackpad responsiveness: unverified; process state does not prove frame delivery.
      """
  }

  private func pointsToManagedPlist(_ path: URL?) -> Bool {
    guard let path else { return false }
    return path.resolvingSymlinksInPath().path == managedPlistURL.resolvingSymlinksInPath().path
  }

  private func exitDescription(_ status: Int32?) -> String {
    status.map { ", last exit status: \($0)" } ?? ""
  }
}

public enum LaunchAgentServiceError: Error, CustomStringConvertible {
  case invalidExecutable(URL)
  case invalidConfiguration(URL, String)
  case foreignPlist(URL)
  case plistRead(URL, String)
  case plistWrite(URL, String)
  case launchctl(String)
  case rollback(String)
  case alreadyRunningConflict

  public var description: String {
    switch self {
    case .invalidExecutable(let url): return "Stable executable is missing or not executable: \(url.path)"
    case .invalidConfiguration(let url, let reason):
      return "Invalid configuration at \(url.path): \(reason)"
    case .foreignPlist(let url):
      return "Refusing to change unmanaged or malformed LaunchAgent plist at \(url.path)"
    case .plistRead(let url, let reason):
      return "Cannot read LaunchAgent plist at \(url.path): \(reason)"
    case .plistWrite(let url, let reason):
      return "Cannot update LaunchAgent plist at \(url.path): \(reason)"
    case .launchctl(let reason): return "launchctl failed: \(reason)"
    case .rollback(let reason): return "LaunchAgent operation failed and rollback was incomplete: \(reason)"
    case .alreadyRunningConflict:
      return "Another aerospace-gestures listener already holds the instance lock"
    }
  }
}

public final class LaunchAgentService {
  private let paths: LaunchAgentPaths
  private let processRunner: ExternalProcessRunning
  private let fileManager: FileManager
  private let isExecutable: (String) -> Bool

  public init(
    paths: LaunchAgentPaths,
    processRunner: ExternalProcessRunning = SystemExternalProcessRunner(),
    fileManager: FileManager = .default,
    isExecutable: @escaping (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
  ) {
    self.paths = paths
    self.processRunner = processRunner
    self.fileManager = fileManager
    self.isExecutable = isExecutable
  }

  @discardableResult
  public func install() throws -> ServiceOperationResult {
    try validate(executableURL: paths.executableURL, configurationURL: paths.configurationURL)
    guard try readInstallation().state != .foreign else {
      throw LaunchAgentServiceError.foreignPlist(paths.plistURL)
    }
    return try withOperationLock { try installWhileLocked() }
  }

  private func installWhileLocked() throws -> ServiceOperationResult {
    try validate(executableURL: paths.executableURL, configurationURL: paths.configurationURL)
    let newData = try makePlist(configurationURL: paths.configurationURL)
    let existing = try readInstallation()
    guard existing.state != .foreign else { throw LaunchAgentServiceError.foreignPlist(paths.plistURL) }

    let loaded = try launchdState()
    let wasLoaded = try isLoaded(loaded)
    if existing.state == .absent, wasLoaded {
      throw LaunchAgentServiceError.foreignPlist(paths.plistURL)
    }
    if wasLoaded { try requireLoadedJobBelongsToUs(loaded) }
    if existing.state == .owned, existing.data == newData {
      switch loaded {
      case .running:
        return .alreadyInstalled
      case .loaded:
        try kickstart()
        return .started
      default:
        break
      }
    }

    let wasInstalled = existing.state == .owned
    let oldData = existing.data
    if wasLoaded { try bootout() }

    do {
      try writePlist(newData)
      try ensureNoListener()
      try bootstrap()
      if !wasInstalled { return .installed }
      return oldData == newData ? .started : .updated
    } catch let operationError {
      do {
        if try isLoaded(launchdState()) { try bootout() }
        if let oldData {
          try writePlist(oldData)
          if wasLoaded { try bootstrap() }
        } else {
          try removePlistIfOwned(expectedData: newData)
        }
      } catch let rollbackError {
        throw LaunchAgentServiceError.rollback(
          "\(rollbackError); original operation: \(operationError)")
      }
      throw operationError
    }
  }

  @discardableResult
  public func start() throws -> ServiceOperationResult {
    let data = try requireOwnedInstallation()
    try validate(
      executableURL: paths.executableURL, configurationURL: try configurationURL(from: data))
    return try withOperationLock { try startWhileLocked() }
  }

  private func startWhileLocked() throws -> ServiceOperationResult {
    let installationData = try requireOwnedInstallation()
    let configurationURL = try configurationURL(from: installationData)
    try validate(executableURL: paths.executableURL, configurationURL: configurationURL)
    let state = try launchdState()
    if case .running = state {
      try requireLoadedJobBelongsToUs(state)
      return .alreadyRunning
    }
    if case .loaded = state {
      try requireLoadedJobBelongsToUs(state)
      try kickstart()
      return .started
    }
    guard state == .notLoaded else {
      if case .unknown(let reason) = state { throw LaunchAgentServiceError.launchctl(reason) }
      throw LaunchAgentServiceError.launchctl("launchd state is not safe to start")
    }
    try ensureNoListener()
    try bootstrap()
    return .started
  }

  @discardableResult
  public func stop() throws -> ServiceOperationResult {
    guard try readInstallation().state != .foreign else {
      throw LaunchAgentServiceError.foreignPlist(paths.plistURL)
    }
    return try withOperationLock { try stopWhileLocked() }
  }

  private func stopWhileLocked() throws -> ServiceOperationResult {
    let installation = try readInstallation()
    if installation.state == .foreign { throw LaunchAgentServiceError.foreignPlist(paths.plistURL) }
    guard installation.state == .owned else {
      guard try launchdState() == .notLoaded else {
        throw LaunchAgentServiceError.foreignPlist(paths.plistURL)
      }
      return .alreadyStopped
    }
    guard try isLoaded(launchdState()) else { return .alreadyStopped }
    try bootout()
    return .stopped
  }

  @discardableResult
  public func restart() throws -> ServiceOperationResult {
    let data = try requireOwnedInstallation()
    try validate(
      executableURL: paths.executableURL, configurationURL: try configurationURL(from: data))
    return try withOperationLock { try restartWhileLocked() }
  }

  private func restartWhileLocked() throws -> ServiceOperationResult {
    let installationData = try requireOwnedInstallation()
    let configurationURL = try configurationURL(from: installationData)
    try validate(executableURL: paths.executableURL, configurationURL: configurationURL)
    let wasLoaded = try isLoaded(launchdState())
    if wasLoaded { try bootout() }
    do {
      try ensureNoListener()
      try bootstrap()
    } catch let restartError {
      if wasLoaded {
        do {
          if try !isLoaded(launchdState()) { try bootstrap() }
        } catch let rollbackError {
          throw LaunchAgentServiceError.rollback(
            "restart failed: \(restartError); rebootstrap failed: \(rollbackError)")
        }
      }
      throw restartError
    }
    return .restarted
  }

  @discardableResult
  public func uninstall() throws -> ServiceOperationResult {
    guard try readInstallation().state != .foreign else {
      throw LaunchAgentServiceError.foreignPlist(paths.plistURL)
    }
    return try withOperationLock { try uninstallWhileLocked() }
  }

  private func uninstallWhileLocked() throws -> ServiceOperationResult {
    let installation = try readInstallation()
    guard installation.state != .foreign else {
      throw LaunchAgentServiceError.foreignPlist(paths.plistURL)
    }
    guard let data = installation.data else {
      guard try launchdState() == .notLoaded else {
        throw LaunchAgentServiceError.foreignPlist(paths.plistURL)
      }
      return .notInstalled
    }

    if try isLoaded(launchdState()) { try bootout() }
    try removePlistIfOwned(expectedData: data)
    return .uninstalled
  }

  public func status() throws -> ServiceStatus {
    let installation = try readInstallation()
    let state: ServiceLaunchState
    do {
      state = try launchdState()
    } catch {
      state = .unknown(String(describing: error))
    }
    let configuration = installation.data.flatMap { try? configurationURL(from: $0) }
      ?? paths.configurationURL
    return ServiceStatus(
      installation: installation.state, launchd: state, configurationURL: configuration,
      managedPlistURL: paths.plistURL)
  }

  private func withOperationLock<T>(_ operation: () throws -> T) throws -> T {
    let lock = try InstanceLock.acquire(
      at: paths.operationLockURL, under: paths.homeDirectory, ownerUID: paths.filesystemUID)
    defer { lock.release() }
    return try operation()
  }

  private func validate(executableURL: URL, configurationURL: URL) throws {
    guard fileManager.isExecutableFile(atPath: executableURL.path) else {
      throw LaunchAgentServiceError.invalidExecutable(executableURL)
    }
    do {
      let configuration = try ConfigurationFile.load(at: configurationURL)
      for binding in configuration.bindings where !isExecutable(binding.command[0]) {
        throw LaunchAgentServiceError.invalidConfiguration(
          configurationURL, "command is not executable: \(binding.command[0])")
      }
    } catch let error as LaunchAgentServiceError {
      throw error
    } catch {
      throw LaunchAgentServiceError.invalidConfiguration(configurationURL, String(describing: error))
    }
  }

  private func makePlist(configurationURL: URL) throws -> Data {
    let properties: [String: Any] = [
      "Label": LaunchAgentPaths.label,
      "ProgramArguments": [paths.executableURL.path, "run", configurationURL.path],
      "WorkingDirectory": paths.homeDirectory.path,
      "RunAtLoad": true,
      "KeepAlive": ["SuccessfulExit": false],
      "ThrottleInterval": 30,
      "StandardOutPath": "/dev/null",
      "StandardErrorPath": "/dev/null",
      "EnvironmentVariables": ["AEROSPACE_GESTURES_MANAGED": "1"],
    ]
    do {
      return try PropertyListSerialization.data(
        fromPropertyList: properties, format: .xml, options: 0)
    } catch {
      throw LaunchAgentServiceError.plistWrite(paths.plistURL, String(describing: error))
    }
  }

  private struct Installation {
    let state: ServiceInstallationState
    let data: Data?
  }

  private func readInstallation() throws -> Installation {
    let directoryState = try launchAgentsDirectoryState()
    guard directoryState == .owned else {
      return Installation(state: directoryState, data: nil)
    }
    var information = stat()
    guard lstat(paths.plistURL.path, &information) == 0 else {
      if errno == ENOENT { return Installation(state: .absent, data: nil) }
      throw LaunchAgentServiceError.plistRead(paths.plistURL, String(cString: strerror(errno)))
    }
    guard (information.st_mode & S_IFMT) == S_IFREG,
      information.st_uid == paths.filesystemUID,
      (information.st_mode & mode_t(S_IWGRP | S_IWOTH)) == 0,
      let data = try? Data(contentsOf: paths.plistURL),
      let properties = try? PropertyListSerialization.propertyList(
        from: data, options: [], format: nil) as? [String: Any],
      owns(properties)
    else {
      return Installation(state: .foreign, data: nil)
    }
    return Installation(state: .owned, data: data)
  }

  private func owns(_ properties: [String: Any]) -> Bool {
    guard properties.count == 9,
      properties["Label"] as? String == LaunchAgentPaths.label,
      (properties["EnvironmentVariables"] as? [String: String]) == [
        "AEROSPACE_GESTURES_MANAGED": "1"
      ],
      let arguments = properties["ProgramArguments"] as? [String], arguments.count == 3,
      arguments[0] == paths.executableURL.path, arguments[1] == "run",
      arguments[2].hasPrefix("/"),
      properties["WorkingDirectory"] as? String == paths.homeDirectory.path,
      properties["RunAtLoad"] as? Bool == true,
      (properties["KeepAlive"] as? [String: Bool]) == ["SuccessfulExit": false],
      properties["ThrottleInterval"] as? Int == 30,
      properties["StandardOutPath"] as? String == "/dev/null",
      properties["StandardErrorPath"] as? String == "/dev/null"
    else { return false }
    return true
  }

  private func configurationURL(from data: Data) throws -> URL {
    guard let properties = try? PropertyListSerialization.propertyList(
      from: data, options: [], format: nil) as? [String: Any],
      let arguments = properties["ProgramArguments"] as? [String], arguments.count == 3,
      arguments[2].hasPrefix("/")
    else { throw LaunchAgentServiceError.foreignPlist(paths.plistURL) }
    return URL(fileURLWithPath: arguments[2]).standardizedFileURL
  }

  private func requireOwnedInstallation() throws -> Data {
    let installation = try readInstallation()
    guard installation.state == .owned, let data = installation.data else {
      throw LaunchAgentServiceError.foreignPlist(paths.plistURL)
    }
    return data
  }

  private func isLoaded(_ state: ServiceLaunchState) throws -> Bool {
    switch state {
    case .notLoaded: return false
    case .running, .loaded: return true
    case .unknown(let reason): throw LaunchAgentServiceError.launchctl(reason)
    }
  }

  private func launchdState() throws -> ServiceLaunchState {
    let result = try processRunner.run(
      executable: paths.launchctlURL, arguments: ["print", paths.serviceTarget])
    guard result.status == 0 else {
      if isNotFound(result) { return .notLoaded }
      throw LaunchAgentServiceError.launchctl(result.stderr.isEmpty ? result.stdout : result.stderr)
    }
    let fields = Dictionary(
      result.stdout.split(separator: "\n").compactMap { line -> (String, String)? in
        guard let separator = line.range(of: " = ") else { return nil }
        return (
          String(line[..<separator.lowerBound]).trimmingCharacters(in: .whitespaces),
          String(line[separator.upperBound...]).trimmingCharacters(in: .whitespaces))
      }, uniquingKeysWith: { first, _ in first })
    guard let state = fields["state"] else {
      return .unknown("launchctl print did not report a state")
    }
    let pid = fields["pid"].flatMap(Int32.init)
    let exit = fields["last exit code"].flatMap { Int32($0.split(separator: " ").first ?? "") }
    let plistPath = fields["path"].flatMap { path -> URL? in
      guard path.hasPrefix("/") else { return nil }
      return URL(fileURLWithPath: path).standardizedFileURL
    }
    if state == "running" {
      return .running(pid: pid, lastExitCode: exit, plistPath: plistPath)
    }
    return .loaded(state: state, pid: pid, lastExitCode: exit, plistPath: plistPath)
  }

  private func isNotFound(_ result: ExternalProcessResult) -> Bool {
    result.status == 113 && (result.stderr + result.stdout).contains("Could not find service")
  }

  private func ensureNoListener() throws {
    do {
      let lock = try InstanceLock.acquire(
        at: paths.instanceLockURL, under: paths.homeDirectory, ownerUID: paths.filesystemUID)
      lock.release()
    } catch InstanceLockError.alreadyHeld {
      throw LaunchAgentServiceError.alreadyRunningConflict
    }
  }

  private func bootstrap() throws {
    let result = try processRunner.run(
      executable: paths.launchctlURL,
      arguments: ["bootstrap", paths.domain, paths.plistURL.path])
    guard result.status == 0 else {
      throw LaunchAgentServiceError.launchctl(result.stderr.isEmpty ? result.stdout : result.stderr)
    }
  }

  private func requireLoadedJobBelongsToUs(_ state: ServiceLaunchState) throws {
    let registeredPath: URL?
    switch state {
    case .running(_, _, let plistPath), .loaded(_, _, _, let plistPath):
      registeredPath = plistPath
    case .notLoaded:
      throw LaunchAgentServiceError.launchctl("LaunchAgent is not loaded")
    case .unknown(let reason): throw LaunchAgentServiceError.launchctl(reason)
    }
    guard let registeredPath,
      registeredPath.resolvingSymlinksInPath().path
        == paths.plistURL.resolvingSymlinksInPath().path
    else { throw LaunchAgentServiceError.foreignPlist(paths.plistURL) }
  }

  private func kickstart() throws {
    let result = try processRunner.run(
      executable: paths.launchctlURL,
      arguments: ["kickstart", "\(paths.domain)/\(LaunchAgentPaths.label)"])
    guard result.status == 0 else {
      throw LaunchAgentServiceError.launchctl(
        "kickstart failed (\(result.status)): \(result.stderr.trimmingCharacters(in: .whitespacesAndNewlines))")
    }
  }

  private func bootout() throws {
    let state = try launchdState()
    guard try isLoaded(state) else { return }
    try requireLoadedJobBelongsToUs(state)
    let result = try processRunner.run(
      executable: paths.launchctlURL, arguments: ["bootout", paths.serviceTarget])
    guard result.status == 0 else {
      if isNotFound(result), try launchdState() == .notLoaded { return }
      throw LaunchAgentServiceError.launchctl(result.stderr.isEmpty ? result.stdout : result.stderr)
    }
  }

  private func writePlist(_ data: Data) throws {
    do {
      try ensureLaunchAgentsDirectoryCanBeCreated()
      try fileManager.createDirectory(
        at: paths.launchAgentsDirectory, withIntermediateDirectories: true)
      guard try launchAgentsDirectoryState() == .owned else {
        throw LaunchAgentServiceError.foreignPlist(paths.plistURL)
      }
      guard try readInstallation().state != .foreign else {
        throw LaunchAgentServiceError.foreignPlist(paths.plistURL)
      }
      try data.write(to: paths.plistURL, options: .atomic)
    } catch {
      throw LaunchAgentServiceError.plistWrite(paths.plistURL, String(describing: error))
    }
  }

  private func launchAgentsDirectoryState() throws -> ServiceInstallationState {
    var homeInformation = stat()
    guard stat(paths.homeDirectory.path, &homeInformation) == 0 else {
      if errno == ENOENT { return .absent }
      throw LaunchAgentServiceError.plistRead(paths.homeDirectory, String(cString: strerror(errno)))
    }
    guard isTrustedDirectory(homeInformation) else { return .foreign }

    let libraryDirectory = paths.homeDirectory.appendingPathComponent("Library", isDirectory: true)
    for directory in [libraryDirectory, paths.launchAgentsDirectory] {
      var information = stat()
      guard lstat(directory.path, &information) == 0 else {
        if errno == ENOENT { return .absent }
        throw LaunchAgentServiceError.plistRead(directory, String(cString: strerror(errno)))
      }
      guard isTrustedDirectory(information) else { return .foreign }
    }
    return .owned
  }

  private func ensureLaunchAgentsDirectoryCanBeCreated() throws {
    var homeInformation = stat()
    guard stat(paths.homeDirectory.path, &homeInformation) == 0,
      isTrustedDirectory(homeInformation)
    else { throw LaunchAgentServiceError.foreignPlist(paths.plistURL) }

    let libraryDirectory = paths.homeDirectory.appendingPathComponent("Library", isDirectory: true)
    for directory in [libraryDirectory, paths.launchAgentsDirectory] {
      var information = stat()
      if lstat(directory.path, &information) == 0 {
        guard isTrustedDirectory(information) else {
          throw LaunchAgentServiceError.foreignPlist(paths.plistURL)
        }
      } else if errno != ENOENT {
        throw LaunchAgentServiceError.plistRead(directory, String(cString: strerror(errno)))
      }
    }
  }

  private func isTrustedDirectory(_ information: stat) -> Bool {
    (information.st_mode & S_IFMT) == S_IFDIR
      && information.st_uid == getuid()
      && (information.st_mode & mode_t(S_IWGRP | S_IWOTH)) == 0
  }

  private func removePlistIfOwned(expectedData: Data) throws {
    let current = try readInstallation()
    if current.state == .absent { return }
    guard current.state == .owned, current.data == expectedData else {
      throw LaunchAgentServiceError.foreignPlist(paths.plistURL)
    }
    do {
      try fileManager.removeItem(at: paths.plistURL)
    } catch {
      throw LaunchAgentServiceError.plistWrite(paths.plistURL, String(describing: error))
    }
  }
}
