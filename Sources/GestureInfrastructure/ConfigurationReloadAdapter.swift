import Darwin
import Foundation
import GestureCore

public struct ConfigurationReloadSourcePaths: Sendable {
  public let launchAgentPlistURL: URL
  public let managedConfigurationURL: URL
  public let storeDirectoryURL: URL

  public init(
    launchAgentPlistURL: URL = URL(
      fileURLWithPath: "/Library/LaunchAgents/com.aerospace-gestures.plist"),
    managedConfigurationURL: URL = URL(
      fileURLWithPath: "/etc/aerospace-gestures/config.json"),
    storeDirectoryURL: URL = URL(fileURLWithPath: "/nix/store", isDirectory: true)
  ) {
    self.launchAgentPlistURL = launchAgentPlistURL.standardizedFileURL
    self.managedConfigurationURL = managedConfigurationURL.standardizedFileURL
    self.storeDirectoryURL = storeDirectoryURL.standardizedFileURL
  }
}

/// Resolves the file afresh on each reload, so Nix-managed runs follow the current /etc symlink.
public struct ConfigurationReloadSourceResolver: Sendable {
  public static let nixManagedEnvironmentKey = "AEROSPACE_GESTURES_NIX_MANAGED"
  public static let launchAgentLabel = "com.aerospace-gestures"

  private let nixManaged: Bool
  private let fallbackURL: URL
  private let currentExecutableURL: URL
  private let paths: ConfigurationReloadSourcePaths
  private let trustedOwnerUID: uid_t
  private let isExecutable: @Sendable (String) -> Bool

  public init(
    nixManaged: Bool,
    fallbackURL: URL,
    currentExecutableURL: URL,
    paths: ConfigurationReloadSourcePaths = ConfigurationReloadSourcePaths(),
    trustedOwnerUID: uid_t = 0,
    isExecutable: @escaping @Sendable (String) -> Bool = {
      FileManager.default.isExecutableFile(atPath: $0)
    }
  ) {
    self.nixManaged = nixManaged
    self.fallbackURL = fallbackURL.standardizedFileURL
    self.currentExecutableURL = currentExecutableURL.standardizedFileURL
    self.paths = paths
    self.trustedOwnerUID = trustedOwnerUID
    self.isExecutable = isExecutable
  }

  public func resolve() throws -> URL {
    guard nixManaged else { return fallbackURL }

    try validateDirectory(paths.launchAgentPlistURL.deletingLastPathComponent())
    try validateRegularFile(paths.launchAgentPlistURL, requireNonWritable: true)

    let data = try Data(contentsOf: paths.launchAgentPlistURL)
    guard
      let properties = try? PropertyListSerialization.propertyList(
        from: data, options: [], format: nil) as? [String: Any]
    else {
      throw ConfigurationReloadSourceError.invalidPlist(paths.launchAgentPlistURL)
    }
    guard properties["Label"] as? String == Self.launchAgentLabel else {
      throw ConfigurationReloadSourceError.invalidLabel(paths.launchAgentPlistURL)
    }
    let environment = properties["EnvironmentVariables"] as? [String: String]
    guard environment?[Self.nixManagedEnvironmentKey] == "1" else {
      throw ConfigurationReloadSourceError.invalidNixMarker(paths.launchAgentPlistURL)
    }
    guard
      let arguments = properties["ProgramArguments"] as? [String], arguments.count == 3,
      arguments[0].hasPrefix("/"), arguments[1] == "run", arguments[2].hasPrefix("/")
    else {
      throw ConfigurationReloadSourceError.invalidProgramArguments(paths.launchAgentPlistURL)
    }

    let expectedExecutable = currentExecutableURL.path
    guard arguments[0] == expectedExecutable else {
      throw ConfigurationReloadSourceError.executableMismatch(
        expected: expectedExecutable, actual: arguments[0])
    }
    guard isExecutable(arguments[0]) else {
      throw ConfigurationReloadSourceError.executableUnavailable(arguments[0])
    }

    let expectedConfiguration = paths.managedConfigurationURL.path
    guard arguments[2] == expectedConfiguration else {
      throw ConfigurationReloadSourceError.configurationPathMismatch(
        expected: expectedConfiguration, actual: arguments[2])
    }
    try validateManagedConfigurationSymlink()
    return paths.managedConfigurationURL
  }

  private func validateManagedConfigurationSymlink() throws {
    let configurationURL = paths.managedConfigurationURL
    try validateDirectory(configurationURL.deletingLastPathComponent())
    let information = try fileInformation(at: configurationURL)
    guard
      (information.st_mode & S_IFMT) == S_IFLNK,
      information.st_uid == trustedOwnerUID
    else {
      throw ConfigurationReloadSourceError.unsafeConfigurationPath(
        configurationURL, "expected a user-independent symlink owned by the trusted UID")
    }

    try validateDirectory(paths.storeDirectoryURL)
    let resolvedURL = configurationURL.resolvingSymlinksInPath().standardizedFileURL
    let storePath =
      paths.storeDirectoryURL.path.hasSuffix("/")
      ? paths.storeDirectoryURL.path : paths.storeDirectoryURL.path + "/"
    guard
      resolvedURL.path.hasPrefix(storePath),
      resolvedURL.lastPathComponent.hasSuffix("-aerospace-gestures.json")
    else {
      throw ConfigurationReloadSourceError.unsafeConfigurationPath(
        configurationURL,
        "target must be an aerospace-gestures JSON file under the trusted Nix store")
    }
    try validateRegularFile(resolvedURL, requireNonWritable: true)
  }

  private func validateDirectory(_ url: URL) throws {
    let information = try fileInformation(at: url)
    guard
      (information.st_mode & S_IFMT) == S_IFDIR,
      information.st_uid == trustedOwnerUID,
      (information.st_mode & mode_t(S_IWGRP | S_IWOTH)) == 0
    else {
      throw ConfigurationReloadSourceError.unsafePath(
        url, "directory must be trusted-owned and not group/world-writable")
    }
  }

  func validateRegularFile(_ url: URL, requireNonWritable: Bool) throws {
    let information = try fileInformation(at: url)
    let writableMask = mode_t(S_IWUSR | S_IWGRP | S_IWOTH)
    guard
      (information.st_mode & S_IFMT) == S_IFREG,
      information.st_uid == trustedOwnerUID,
      !requireNonWritable || (information.st_mode & writableMask) == 0
    else {
      throw ConfigurationReloadSourceError.unsafePath(
        url, "file must be regular, trusted-owned, and non-writable")
    }
  }

  private func fileInformation(at url: URL) throws -> stat {
    var information = stat()
    let result = url.path.withCString { Darwin.lstat($0, &information) }
    guard result == 0 else {
      throw ConfigurationReloadSourceError.unsafePath(
        url, String(cString: strerror(errno)))
    }
    return information
  }
}

/// Resolves, decodes, and validates a complete candidate before returning it for atomic activation.
public struct ConfigurationReloadAdapter: Sendable {
  private let sourceResolver: ConfigurationReloadSourceResolver
  private let validate: @Sendable (Configuration) throws -> Void

  public init(
    sourceResolver: ConfigurationReloadSourceResolver,
    validate: @escaping @Sendable (Configuration) throws -> Void
  ) {
    self.sourceResolver = sourceResolver
    self.validate = validate
  }

  public func load() throws -> Configuration {
    let sourceURL = try sourceResolver.resolve()
    let configuration = try ConfigurationFile.load(at: sourceURL)
    try validate(configuration)
    return configuration
  }
}

public enum ConfigurationReloadSourceError: Error, CustomStringConvertible {
  case unsafePath(URL, String)
  case invalidPlist(URL)
  case invalidLabel(URL)
  case invalidNixMarker(URL)
  case invalidProgramArguments(URL)
  case executableMismatch(expected: String, actual: String)
  case executableUnavailable(String)
  case configurationPathMismatch(expected: String, actual: String)
  case unsafeConfigurationPath(URL, String)

  public var description: String {
    switch self {
    case .unsafePath(let url, let reason):
      return "Untrusted managed configuration path at \(url.path): \(reason)"
    case .invalidPlist(let url):
      return "Cannot read a valid managed LaunchAgent plist at \(url.path)"
    case .invalidLabel(let url):
      return
        "Managed LaunchAgent Label is not \(ConfigurationReloadSourceResolver.launchAgentLabel) at \(url.path)"
    case .invalidNixMarker(let url):
      return "Managed LaunchAgent lacks the Nix reload marker at \(url.path)"
    case .invalidProgramArguments(let url):
      return
        "Managed LaunchAgent ProgramArguments must be [executable, run, absolute config path] at \(url.path)"
    case .executableMismatch(let expected, let actual):
      return
        "Managed LaunchAgent executable does not match this process (expected \(expected), got \(actual))"
    case .executableUnavailable(let path):
      return "Managed LaunchAgent executable is not executable: \(path)"
    case .configurationPathMismatch(let expected, let actual):
      return "Managed LaunchAgent config path must be \(expected), got \(actual)"
    case .unsafeConfigurationPath(let url, let reason):
      return "Untrusted managed config symlink at \(url.path): \(reason)"
    }
  }
}
