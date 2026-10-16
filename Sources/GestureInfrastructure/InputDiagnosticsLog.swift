import Foundation

/// Persists only caller-formatted, single-line aggregate diagnostics to a private bounded file.
public final class InputDiagnosticsLog {
  public static let maximumBytes = 1024 * 1024
  public static let maximumLineBytes = 4096

  public let fileURL: URL

  private let file: CommandOutputLog
  private let writeToStdout: (String) -> Void
  private let writeToStderr: (String) -> Void
  private let lock = NSLock()
  private var didReportFailure = false

  public init(
    homeDirectory: URL,
    expectedUID: uid_t = getuid(),
    maximumBytes: Int = InputDiagnosticsLog.maximumBytes,
    writeToStdout: @escaping (String) -> Void,
    writeToStderr: @escaping (String) -> Void
  ) {
    fileURL = homeDirectory.appendingPathComponent(
      "Library/Logs/aerospace-gestures/input-diagnostics.log")
    file = CommandOutputLog(
      fileURL: fileURL,
      rootURL: homeDirectory,
      expectedUID: expectedUID,
      maximumBytes: maximumBytes)
    self.writeToStdout = writeToStdout
    self.writeToStderr = writeToStderr
  }

  public func emit(_ line: String) {
    lock.lock()
    defer { lock.unlock() }

    let bytes = Array(line.utf8)
    guard !bytes.isEmpty,
      bytes.count <= Self.maximumLineBytes,
      bytes.allSatisfy({ $0 >= 0x20 && $0 <= 0x7e })
    else {
      reportFailure("Rejected invalid input diagnostics line.")
      return
    }

    let record = line + "\n"
    writeToStdout(record)
    do {
      try file.appendDiagnosticLine(line)
    } catch {
      reportFailure(
        "Cannot write input diagnostics at \(fileURL.path); continuing with stdout only.")
    }
  }

  private func reportFailure(_ message: String) {
    guard !didReportFailure else { return }
    didReportFailure = true
    writeToStderr("\(message)\n")
  }
}
