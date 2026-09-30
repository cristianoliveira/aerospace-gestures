import Darwin
import Foundation
import GestureCore

public enum ConfigurationFile {
  public static let defaultContents = #"""
    {
      "threshold": 0.15,
      "bindings": [
        {
          "fingers": 3,
          "direction": "down",
          "command": [
            "/usr/bin/osascript",
            "-e",
            "display dialog \"It's hooked!\" with title \"Three-finger swipe down\" buttons {\"OK\"} default button \"OK\" giving up after 3"
          ]
        }
      ]
    }
    """#

  public static func load(at url: URL) throws -> Configuration {
    let data: Data
    do {
      data = try Data(contentsOf: url)
    } catch {
      throw ConfigurationFileError.cannotRead(path: url.path, reason: error.localizedDescription)
    }
    return try Configuration.load(data)
  }

  public static func initializeDefault(at url: URL) throws {
    let directory = url.deletingLastPathComponent()
    do {
      try FileManager.default.createDirectory(
        at: directory, withIntermediateDirectories: true)
    } catch {
      throw ConfigurationFileError.cannotCreateDirectory(
        path: directory.path, reason: error.localizedDescription)
    }

    let descriptor = Darwin.open(
      url.path, O_WRONLY | O_CREAT | O_EXCL, mode_t(S_IRUSR | S_IWUSR))
    guard descriptor >= 0 else {
      throw ConfigurationFileError.cannotCreate(
        path: url.path, reason: String(cString: strerror(errno)))
    }

    do {
      try write(defaultContents, to: descriptor, path: url.path)
      guard Darwin.close(descriptor) == 0 else {
        throw ConfigurationFileError.cannotWrite(
          path: url.path, reason: String(cString: strerror(errno)))
      }
    } catch {
      _ = Darwin.close(descriptor)
      _ = Darwin.unlink(url.path)
      throw error
    }
  }

  private static func write(_ contents: String, to descriptor: Int32, path: String) throws {
    let data = Data(contents.utf8)
    try data.withUnsafeBytes { bytes in
      guard let baseAddress = bytes.baseAddress else { return }
      var offset = 0
      while offset < bytes.count {
        let result = Darwin.write(
          descriptor, baseAddress.advanced(by: offset), bytes.count - offset)
        if result < 0 {
          if errno == EINTR { continue }
          throw ConfigurationFileError.cannotWrite(
            path: path, reason: String(cString: strerror(errno)))
        }
        guard result > 0 else {
          throw ConfigurationFileError.cannotWrite(path: path, reason: "write made no progress")
        }
        offset += result
      }
    }
  }
}

public enum ConfigurationFileError: Error, CustomStringConvertible {
  case cannotRead(path: String, reason: String)
  case cannotCreateDirectory(path: String, reason: String)
  case cannotCreate(path: String, reason: String)
  case cannotWrite(path: String, reason: String)

  public var description: String {
    switch self {
    case .cannotRead(let path, let reason):
      return "Cannot read configuration at \(path): \(reason)"
    case .cannotCreateDirectory(let path, let reason):
      return "Cannot create configuration directory at \(path): \(reason)"
    case .cannotCreate(let path, let reason):
      return "Cannot create configuration at \(path): \(reason)"
    case .cannotWrite(let path, let reason):
      return "Cannot write configuration at \(path): \(reason)"
    }
  }
}
