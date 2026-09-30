import Darwin
import Foundation

/// A fixed, privacy-safe startup failure category. No free-form error text is stored.
public enum StartupDiagnostic: Equatable {
  case configurationValidationFailed
  case listenerLockUnavailable
  case inputInitializationFailed
  case privateFrameworkUnavailable
  case privateSymbolsUnavailable
  case noMultitouchDevices

  fileprivate var stage: String {
    switch self {
    case .configurationValidationFailed: return "configuration"
    case .listenerLockUnavailable: return "listener-lock"
    case .inputInitializationFailed, .privateFrameworkUnavailable,
      .privateSymbolsUnavailable, .noMultitouchDevices:
      return "input-initialization"
    }
  }

  fileprivate var category: String {
    switch self {
    case .configurationValidationFailed: return "validation-failed"
    case .listenerLockUnavailable: return "unavailable"
    case .inputInitializationFailed: return "failed"
    case .privateFrameworkUnavailable: return "framework-unavailable"
    case .privateSymbolsUnavailable: return "symbols-unavailable"
    case .noMultitouchDevices: return "no-devices"
    }
  }

  public var description: String {
    switch self {
    case .configurationValidationFailed: return "configuration validation failed"
    case .listenerLockUnavailable: return "listener lock unavailable"
    case .inputInitializationFailed: return "input initialization failed"
    case .privateFrameworkUnavailable: return "private MultitouchSupport framework unavailable"
    case .privateSymbolsUnavailable: return "private multitouch symbols unavailable"
    case .noMultitouchDevices: return "no multitouch devices found"
    }
  }

  public static func inputInitializationFailure(for message: String) -> Self {
    switch message {
    case "Cannot load private MultitouchSupport framework on this macOS version":
      return .privateFrameworkUnavailable
    case "Required private multitouch symbols are unavailable on this macOS version":
      return .privateSymbolsUnavailable
    case "No multitouch devices found; connect a trackpad and retry":
      return .noMultitouchDevices
    default:
      return .inputInitializationFailed
    }
  }

  fileprivate static func parse(stage: String, category: String) -> Self? {
    switch (stage, category) {
    case ("configuration", "validation-failed"): return .configurationValidationFailed
    case ("listener-lock", "unavailable"): return .listenerLockUnavailable
    case ("input-initialization", "failed"): return .inputInitializationFailed
    case ("input-initialization", "framework-unavailable"): return .privateFrameworkUnavailable
    case ("input-initialization", "symbols-unavailable"): return .privateSymbolsUnavailable
    case ("input-initialization", "no-devices"): return .noMultitouchDevices
    default: return nil
    }
  }
}

/// Keeps only one private, bounded record. It stores fixed categories, never error details.
public struct StartupDiagnosticStore {
  public static let maximumBytes = 128

  private let fileURL: URL
  private let rootURL: URL
  private let expectedUID: uid_t

  public init(fileURL: URL, rootURL: URL, expectedUID: uid_t = getuid()) {
    self.fileURL = fileURL.standardizedFileURL
    self.rootURL = rootURL.standardizedFileURL
    self.expectedUID = expectedUID
  }

  public func record(_ diagnostic: StartupDiagnostic) throws {
    let contents = Data(
      "version=1\nstage=\(diagnostic.stage)\ncategory=\(diagnostic.category)\n".utf8)
    guard contents.count <= Self.maximumBytes else {
      throw StartupDiagnosticStoreError.recordTooLarge
    }

    guard let directory = try openTrustedDirectory() else {
      throw StartupDiagnosticStoreError.directoryMissing
    }
    defer { close(directory) }

    var descriptor = openat(
      directory, fileURL.lastPathComponent,
      O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_NONBLOCK, mode_t(0o600))
    let created = descriptor >= 0
    if !created, errno == EEXIST {
      descriptor = openat(directory, fileURL.lastPathComponent, O_RDWR | O_NOFOLLOW | O_NONBLOCK)
    }
    guard descriptor >= 0 else { throw StartupDiagnosticStoreError.file(errno) }
    defer { close(descriptor) }
    if created, fchmod(descriptor, mode_t(0o600)) != 0 {
      throw StartupDiagnosticStoreError.file(errno)
    }

    let information = try validatePrivateFile(descriptor)
    if !created {
      guard information.st_size >= 0,
        information.st_size <= off_t(Self.maximumBytes)
      else { throw StartupDiagnosticStoreError.recordTooLarge }
      _ = try decode(readBounded(from: descriptor))
      guard lseek(descriptor, 0, SEEK_SET) == 0 else {
        throw StartupDiagnosticStoreError.file(errno)
      }
    }
    guard ftruncate(descriptor, 0) == 0 else { throw StartupDiagnosticStoreError.file(errno) }
    try write(contents, to: descriptor)
  }

  public func read() throws -> StartupDiagnostic? {
    guard let directory = try openTrustedDirectory() else {
      throw StartupDiagnosticStoreError.directoryMissing
    }
    defer { close(directory) }

    let descriptor = openat(
      directory, fileURL.lastPathComponent, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
    guard descriptor >= 0 else {
      if errno == ENOENT { return nil }
      throw StartupDiagnosticStoreError.file(errno)
    }
    defer { close(descriptor) }

    let information = try validatePrivateFile(descriptor)
    guard information.st_size >= 0,
      information.st_size <= off_t(Self.maximumBytes)
    else { throw StartupDiagnosticStoreError.recordTooLarge }

    return try decode(readBounded(from: descriptor))
  }

  public func clear() throws {
    guard let directory = try openTrustedDirectory() else { return }
    defer { close(directory) }

    let descriptor = openat(
      directory, fileURL.lastPathComponent, O_RDONLY | O_NOFOLLOW | O_NONBLOCK)
    guard descriptor >= 0 else {
      if errno == ENOENT { return }
      throw StartupDiagnosticStoreError.file(errno)
    }
    defer { close(descriptor) }
    let information = try validatePrivateFile(descriptor)
    guard information.st_size >= 0,
      information.st_size <= off_t(Self.maximumBytes)
    else { throw StartupDiagnosticStoreError.recordTooLarge }
    _ = try decode(readBounded(from: descriptor))

    guard unlinkat(directory, fileURL.lastPathComponent, 0) == 0 else {
      if errno == ENOENT { return }
      throw StartupDiagnosticStoreError.file(errno)
    }
  }

  private func decode(_ contents: Data) throws -> StartupDiagnostic {
    guard contents.count <= Self.maximumBytes,
      let text = String(data: contents, encoding: .utf8)
    else { throw StartupDiagnosticStoreError.invalidRecord }

    let fields = text.split(separator: "\n", omittingEmptySubsequences: true)
    guard fields.count == 3, fields[0] == "version=1",
      fields[1].hasPrefix("stage="), fields[2].hasPrefix("category="),
      let diagnostic = StartupDiagnostic.parse(
        stage: String(fields[1].dropFirst("stage=".count)),
        category: String(fields[2].dropFirst("category=".count)))
    else { throw StartupDiagnosticStoreError.invalidRecord }
    return diagnostic
  }

  private func openTrustedDirectory() throws -> Int32? {
    let lexicalRoot = rootURL.path
    let parentPath = fileURL.deletingLastPathComponent().path
    let rootPrefix = lexicalRoot.hasSuffix("/") ? lexicalRoot : lexicalRoot + "/"
    guard parentPath.hasPrefix(rootPrefix) else {
      throw StartupDiagnosticStoreError.untrustedLocation
    }
    let components = parentPath.dropFirst(rootPrefix.count).split(separator: "/")
    let resolvedRoot = rootURL.resolvingSymlinksInPath().standardizedFileURL
    var directory = open(resolvedRoot.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
    guard directory >= 0 else {
      if errno == ENOENT { return nil }
      throw StartupDiagnosticStoreError.file(errno)
    }

    do {
      try validateTrustedDirectory(directory)
      for component in components {
        let child = openat(directory, String(component), O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard child >= 0 else {
          let error = errno
          if error == ENOENT {
            close(directory)
            return nil
          }
          throw StartupDiagnosticStoreError.file(error)
        }
        do {
          try validateTrustedDirectory(child)
        } catch {
          close(child)
          throw error
        }
        close(directory)
        directory = child
      }
      return directory
    } catch {
      close(directory)
      throw error
    }
  }

  private func validateTrustedDirectory(_ descriptor: Int32) throws {
    var information = stat()
    guard fstat(descriptor, &information) == 0 else {
      throw StartupDiagnosticStoreError.file(errno)
    }
    guard (information.st_mode & S_IFMT) == S_IFDIR,
      information.st_uid == expectedUID,
      (information.st_mode & mode_t(S_IWGRP | S_IWOTH)) == 0
    else { throw StartupDiagnosticStoreError.untrustedLocation }
  }

  @discardableResult
  private func validatePrivateFile(_ descriptor: Int32) throws -> stat {
    var information = stat()
    guard fstat(descriptor, &information) == 0 else {
      throw StartupDiagnosticStoreError.file(errno)
    }
    guard (information.st_mode & S_IFMT) == S_IFREG,
      information.st_uid == expectedUID,
      information.st_nlink == 1,
      (information.st_mode & mode_t(0o777)) == mode_t(0o600)
    else { throw StartupDiagnosticStoreError.untrustedLocation }
    return information
  }

  private func write(_ contents: Data, to descriptor: Int32) throws {
    try contents.withUnsafeBytes { bytes in
      guard let baseAddress = bytes.baseAddress else { return }
      var offset = 0
      while offset < bytes.count {
        let count = Darwin.write(descriptor, baseAddress.advanced(by: offset), bytes.count - offset)
        if count < 0, errno == EINTR { continue }
        guard count > 0 else { throw StartupDiagnosticStoreError.file(errno) }
        offset += count
      }
    }
    guard fsync(descriptor) == 0 else { throw StartupDiagnosticStoreError.file(errno) }
  }

  private func readBounded(from descriptor: Int32) throws -> Data {
    var contents = Data()
    var buffer = [UInt8](repeating: 0, count: Self.maximumBytes + 1)
    while contents.count < buffer.count {
      let count = buffer.withUnsafeMutableBytes { bytes in
        Darwin.read(descriptor, bytes.baseAddress!, bytes.count)
      }
      if count < 0, errno == EINTR { continue }
      guard count >= 0 else { throw StartupDiagnosticStoreError.file(errno) }
      if count == 0 { break }
      contents.append(contentsOf: buffer[0..<count])
    }
    return contents
  }
}

public enum StartupDiagnosticStoreError: Error {
  case directoryMissing
  case file(Int32)
  case invalidRecord
  case recordTooLarge
  case untrustedLocation
}
