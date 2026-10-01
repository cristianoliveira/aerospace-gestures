import Darwin
import Foundation

/// A kernel advisory lock shared by foreground and LaunchAgent listeners.
/// The lock file is intentionally retained; lock ownership never depends on a PID file.
public final class InstanceLock {
  private let stateLock = NSLock()
  private var descriptor: Int32?
  public let url: URL

  private init(descriptor: Int32, url: URL) {
    self.descriptor = descriptor
    self.url = url
  }

  public static func acquire(
    at url: URL,
    under rootURL: URL,
    waitForContention: Bool = false,
    pollInterval: TimeInterval = 0.5,
    ownerUID: uid_t = getuid(),
    sleep: (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) }
  ) throws -> InstanceLock {
    while true {
      do {
        return try acquireOnce(at: url, under: rootURL, ownerUID: ownerUID)
      } catch InstanceLockError.alreadyHeld {
        guard waitForContention else { throw InstanceLockError.alreadyHeld(url) }
        sleep(pollInterval)
      }
    }
  }

  private static func acquireOnce(at url: URL, under rootURL: URL, ownerUID: uid_t) throws
    -> InstanceLock
  {
    let parentURL = url.deletingLastPathComponent().standardizedFileURL
    let lexicalRoot = rootURL.standardizedFileURL.path
    let rootPrefix = lexicalRoot.hasSuffix("/") ? lexicalRoot : lexicalRoot + "/"
    guard parentURL.path.hasPrefix(rootPrefix) else {
      throw InstanceLockError.cannotOpen(url, "lock path is outside its allowed root")
    }

    let relativePath = String(parentURL.path.dropFirst(rootPrefix.count))
    let components = relativePath.split(separator: "/").map(String.init)
    let resolvedRoot = rootURL.resolvingSymlinksInPath().standardizedFileURL
    var directoryDescriptor = Darwin.open(
      resolvedRoot.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
    guard directoryDescriptor >= 0 else {
      throw InstanceLockError.cannotOpen(url, String(cString: strerror(errno)))
    }
    var currentDirectoryURL = resolvedRoot
    do {
      try validateDirectoryDescriptor(
        directoryDescriptor, at: currentDirectoryURL, ownerUID: ownerUID)
    } catch {
      _ = Darwin.close(directoryDescriptor)
      throw error
    }

    for component in components {
      do {
        try validateDirectoryDescriptor(
          directoryDescriptor, at: currentDirectoryURL, ownerUID: ownerUID)
      } catch {
        _ = Darwin.close(directoryDescriptor)
        throw error
      }
      var child = openat(
        directoryDescriptor, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
      if child < 0, errno == ENOENT {
        guard mkdirat(directoryDescriptor, component, mode_t(S_IRWXU)) == 0 || errno == EEXIST
        else {
          let reason = String(cString: strerror(errno))
          _ = Darwin.close(directoryDescriptor)
          throw InstanceLockError.cannotOpen(url, reason)
        }
        child = openat(directoryDescriptor, component, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
      }
      guard child >= 0 else {
        let reason = String(cString: strerror(errno))
        _ = Darwin.close(directoryDescriptor)
        throw InstanceLockError.cannotOpen(url, reason)
      }
      currentDirectoryURL.appendPathComponent(component, isDirectory: true)
      do {
        try validateDirectoryDescriptor(child, at: currentDirectoryURL, ownerUID: ownerUID)
      } catch {
        _ = Darwin.close(child)
        _ = Darwin.close(directoryDescriptor)
        throw error
      }
      _ = Darwin.close(directoryDescriptor)
      directoryDescriptor = child
    }
    defer { _ = Darwin.close(directoryDescriptor) }

    let lockName = url.lastPathComponent
    let descriptor = openat(
      directoryDescriptor, lockName, O_CREAT | O_RDWR | O_NOFOLLOW,
      mode_t(S_IRUSR | S_IWUSR))
    guard descriptor >= 0 else {
      throw InstanceLockError.cannotOpen(url, String(cString: strerror(errno)))
    }
    var information = stat()
    guard fstat(descriptor, &information) == 0,
      (information.st_mode & S_IFMT) == S_IFREG,
      information.st_uid == ownerUID, information.st_nlink == 1,
      (information.st_mode & mode_t(S_IRWXG | S_IRWXO)) == 0
    else {
      _ = Darwin.close(descriptor)
      throw InstanceLockError.cannotOpen(
        url, "lock must be a private, user-owned regular file with one link")
    }
    guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
      let reason = errno
      _ = Darwin.close(descriptor)
      if reason == EWOULDBLOCK || reason == EAGAIN {
        throw InstanceLockError.alreadyHeld(url)
      }
      throw InstanceLockError.cannotLock(url, String(cString: strerror(reason)))
    }
    return InstanceLock(descriptor: descriptor, url: url)
  }

  private static func validateDirectoryDescriptor(
    _ descriptor: Int32, at url: URL, ownerUID: uid_t
  ) throws {
    var information = stat()
    guard fstat(descriptor, &information) == 0,
      (information.st_mode & S_IFMT) == S_IFDIR,
      information.st_uid == ownerUID,
      (information.st_mode & mode_t(S_IWGRP | S_IWOTH)) == 0
    else {
      throw InstanceLockError.cannotOpen(
        url, "lock path directory must be user-owned and not group/world-writable")
    }
  }

  public func release() {
    stateLock.lock()
    defer { stateLock.unlock() }
    guard let descriptor else { return }
    self.descriptor = nil
    _ = flock(descriptor, LOCK_UN)
    _ = Darwin.close(descriptor)
  }

  deinit { release() }
}

public enum InstanceLockError: Error, CustomStringConvertible {
  case alreadyHeld(URL)
  case cannotPrepareDirectory(URL, Error)
  case cannotOpen(URL, String)
  case cannotLock(URL, String)

  public var description: String {
    switch self {
    case .alreadyHeld(let url):
      return "Another aerospace-gestures process already holds the lock at \(url.path)"
    case .cannotPrepareDirectory(let url, let error):
      return "Cannot prepare instance lock directory at \(url.path): \(error)"
    case .cannotOpen(let url, let reason):
      return "Cannot open instance lock at \(url.path): \(reason)"
    case .cannotLock(let url, let reason):
      return "Cannot acquire instance lock at \(url.path): \(reason)"
    }
  }
}
