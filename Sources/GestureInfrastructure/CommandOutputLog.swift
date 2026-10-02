import Darwin
import Foundation

/// Appends opt-in command output to a bounded, user-private service log.
public final class CommandOutputLog {
  public static let defaultMaximumBytes = 1024 * 1024

  private let lock = NSLock()
  private let fileURL: URL
  private let rootURL: URL
  private let expectedUID: uid_t
  private let maximumBytes: Int

  public init(
    fileURL: URL,
    rootURL: URL,
    expectedUID: uid_t = getuid(),
    maximumBytes: Int = CommandOutputLog.defaultMaximumBytes
  ) {
    self.fileURL = fileURL.standardizedFileURL
    self.rootURL = rootURL.standardizedFileURL
    self.expectedUID = expectedUID
    self.maximumBytes = max(10, maximumBytes)
  }

  public func append(_ data: Data, from stream: CommandOutputStream) throws {
    guard !data.isEmpty else { return }
    lock.lock()
    defer { lock.unlock() }

    let prefix = Data((stream == .stdout ? "[stdout] " : "[stderr] ").utf8)
    let payload = Data(data.prefix(max(0, maximumBytes - prefix.count - 1)))
    var record = prefix
    record.append(payload)
    record.append(0x0A)

    guard let directory = try openTrustedDirectory(create: true) else {
      throw CommandOutputLogError.directoryUnavailable
    }
    defer { close(directory) }

    let name = fileURL.lastPathComponent
    let descriptor = openat(
      directory, name, O_WRONLY | O_CREAT | O_APPEND | O_NOFOLLOW | O_NONBLOCK,
      mode_t(0o600))
    guard descriptor >= 0 else { throw CommandOutputLogError.file(errno) }
    defer { close(descriptor) }

    var information = stat()
    guard fstat(descriptor, &information) == 0 else { throw CommandOutputLogError.file(errno) }
    guard (information.st_mode & S_IFMT) == S_IFREG,
      information.st_uid == expectedUID,
      information.st_nlink == 1,
      (information.st_mode & mode_t(0o777)) == mode_t(0o600)
    else { throw CommandOutputLogError.untrustedFile }

    let maximumFileSize = off_t(maximumBytes)
    let recordSize = off_t(record.count)
    if information.st_size < 0 || information.st_size > maximumFileSize - recordSize {
      guard ftruncate(descriptor, 0) == 0 else { throw CommandOutputLogError.file(errno) }
    }
    try write(record, to: descriptor)
  }

  private func openTrustedDirectory(create: Bool) throws -> Int32? {
    let rootPath = rootURL.path
    let parentPath = fileURL.deletingLastPathComponent().path
    let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
    guard parentPath.hasPrefix(rootPrefix) else {
      throw CommandOutputLogError.untrustedLocation
    }

    let components = parentPath.dropFirst(rootPrefix.count).split(separator: "/")
    let resolvedRoot = rootURL.resolvingSymlinksInPath().standardizedFileURL
    var directory = open(resolvedRoot.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
    guard directory >= 0 else { throw CommandOutputLogError.file(errno) }
    do {
      try validateDirectory(directory)
      for component in components {
        let name = String(component)
        var child = openat(directory, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        if child < 0, errno == ENOENT, create {
          guard mkdirat(directory, name, mode_t(0o700)) == 0 || errno == EEXIST else {
            throw CommandOutputLogError.file(errno)
          }
          child = openat(directory, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        }
        guard child >= 0 else {
          if errno == ENOENT, !create {
            close(directory)
            return nil
          }
          throw CommandOutputLogError.file(errno)
        }
        do {
          try validateDirectory(child)
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

  private func validateDirectory(_ descriptor: Int32) throws {
    var information = stat()
    guard fstat(descriptor, &information) == 0 else { throw CommandOutputLogError.file(errno) }
    guard (information.st_mode & S_IFMT) == S_IFDIR,
      information.st_uid == expectedUID,
      (information.st_mode & mode_t(S_IWGRP | S_IWOTH)) == 0
    else { throw CommandOutputLogError.untrustedLocation }
  }

  private func write(_ data: Data, to descriptor: Int32) throws {
    try data.withUnsafeBytes { bytes in
      guard let baseAddress = bytes.baseAddress else { return }
      var offset = 0
      while offset < bytes.count {
        let count = Darwin.write(descriptor, baseAddress.advanced(by: offset), bytes.count - offset)
        if count < 0, errno == EINTR { continue }
        guard count > 0 else { throw CommandOutputLogError.file(errno) }
        offset += count
      }
    }
  }
}

public enum CommandOutputLogError: Error {
  case directoryUnavailable
  case file(Int32)
  case untrustedFile
  case untrustedLocation
}
