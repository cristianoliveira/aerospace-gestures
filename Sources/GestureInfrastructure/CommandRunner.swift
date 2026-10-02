import Darwin
import Foundation
import GestureCore

public enum CommandOutputStream: Equatable {
  case stdout
  case stderr
}

/// Main-thread runner. One child at a time; busy gestures are dropped, never queued.
public final class CommandRunner {
  public static let defaultMaximumOutputBytes = 64 * 1024

  private var active: Process?
  private var stopCompletion: (() -> Void)?
  private let timeout: TimeInterval
  private let maximumOutputBytes: Int

  public init(
    timeout: TimeInterval = 5,
    maximumOutputBytes: Int = CommandRunner.defaultMaximumOutputBytes
  ) {
    self.timeout = timeout
    self.maximumOutputBytes = max(0, maximumOutputBytes)
  }

  @discardableResult
  public func run(
    _ command: [String],
    outputHandler: ((CommandOutputStream, Data) -> Void)? = nil,
    completion: @escaping (String) -> Void
  ) -> Bool {
    guard active == nil else { return false }
    guard let executable = command.first else {
      completion("Empty command")
      return false
    }

    let child = Process()
    child.executableURL = URL(fileURLWithPath: executable)
    child.arguments = Array(command.dropFirst())
    child.standardInput = FileHandle.nullDevice

    let capture: CommandOutputCapture?
    let stdoutPipe: Pipe?
    let stderrPipe: Pipe?
    if let outputHandler {
      let stdout = Pipe()
      let stderr = Pipe()
      stdoutPipe = stdout
      stderrPipe = stderr
      capture = CommandOutputCapture(
        stdout: stdout.fileHandleForReading,
        stderr: stderr.fileHandleForReading,
        maximumBytes: maximumOutputBytes,
        outputHandler: outputHandler)
      child.standardOutput = stdout
      child.standardError = stderr
    } else {
      stdoutPipe = nil
      stderrPipe = nil
      capture = nil
      child.standardOutput = FileHandle.nullDevice
      child.standardError = FileHandle.nullDevice
    }

    child.terminationHandler = { [weak self, weak child] process in
      guard let child else { return }
      if let capture {
        capture.childTerminated(status: process.terminationStatus) {
          [weak self, weak child] status in
          DispatchQueue.main.async {
            guard let self, let child else { return }
            self.finish(child, status: status, completion: completion)
          }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
          capture.finishIfReadersRemainOpen()
        }
      } else {
        DispatchQueue.main.async { [weak self] in
          guard let self else { return }
          self.finish(child, status: process.terminationStatus, completion: completion)
        }
      }
    }

    active = child
    do {
      try child.run()
      stdoutPipe?.fileHandleForWriting.closeFile()
      stderrPipe?.fileHandleForWriting.closeFile()
    } catch {
      active = nil
      child.terminationHandler = nil
      capture?.cancel()
      completion("Cannot launch command: \(error.localizedDescription)")
      return false
    }

    DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self, weak child] in
      guard let child, self?.active === child, child.isRunning else { return }
      self?.terminate(child)
    }
    return true
  }

  public func stop(completion: @escaping () -> Void = {}) {
    guard let active, active.isRunning else {
      completion()
      return
    }
    stopCompletion = completion
    terminate(active)
  }

  private func finish(_ child: Process, status: Int32, completion: (String) -> Void) {
    guard active === child else { return }
    child.terminationHandler = nil
    active = nil
    completion("Command exited with status \(status)")
    let stopCompletion = self.stopCompletion
    self.stopCompletion = nil
    stopCompletion?()
  }

  private func terminate(_ child: Process) {
    child.terminate()
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self, weak child] in
      guard let child, self?.active === child, child.isRunning else { return }
      kill(child.processIdentifier, SIGKILL)
    }
  }
}

private final class CommandOutputCapture {
  private let lock = NSLock()
  private let stdout: FileHandle
  private let stderr: FileHandle
  private let maximumBytes: Int
  private let outputHandler: (CommandOutputStream, Data) -> Void
  private var bytesDelivered = 0
  private var truncationReported = false
  private var stdoutEOF = false
  private var stderrEOF = false
  private var childStatus: Int32?
  private var didFinish = false
  private var completion: ((Int32) -> Void)?

  init(
    stdout: FileHandle,
    stderr: FileHandle,
    maximumBytes: Int,
    outputHandler: @escaping (CommandOutputStream, Data) -> Void
  ) {
    self.stdout = stdout
    self.stderr = stderr
    self.maximumBytes = maximumBytes
    self.outputHandler = outputHandler
    self.completion = nil
    stdout.readabilityHandler = { [weak self] handle in self?.read(handle, stream: .stdout) }
    stderr.readabilityHandler = { [weak self] handle in self?.read(handle, stream: .stderr) }
  }

  func childTerminated(status: Int32, completion: @escaping (Int32) -> Void) {
    lock.lock()
    childStatus = status
    self.completion = completion
    let shouldFinish = stdoutEOF && stderrEOF && !didFinish
    if shouldFinish { didFinish = true }
    lock.unlock()
    if shouldFinish { finish(status: status) }
  }

  func finishIfReadersRemainOpen() {
    lock.lock()
    guard !didFinish, let status = childStatus else {
      lock.unlock()
      return
    }
    didFinish = true
    lock.unlock()
    closeReaders()
    finish(status: status)
  }

  func cancel() {
    lock.lock()
    didFinish = true
    lock.unlock()
    closeReaders()
  }

  private func read(_ handle: FileHandle, stream: CommandOutputStream) {
    let data = handle.availableData
    guard !data.isEmpty else {
      markEOF(stream)
      return
    }
    deliver(data, stream: stream)
  }

  private func deliver(_ data: Data, stream: CommandOutputStream) {
    lock.lock()
    guard !didFinish else {
      lock.unlock()
      return
    }
    let available = max(0, maximumBytes - bytesDelivered)
    let acceptedCount = min(available, data.count)
    bytesDelivered += acceptedCount
    let accepted = acceptedCount == data.count ? data : Data(data.prefix(acceptedCount))
    let shouldReportTruncation = acceptedCount < data.count && !truncationReported
    if shouldReportTruncation { truncationReported = true }
    lock.unlock()

    if !accepted.isEmpty { outputHandler(stream, accepted) }
    if shouldReportTruncation {
      outputHandler(.stderr, Data("\n[command output truncated]\n".utf8))
    }
  }

  private func markEOF(_ stream: CommandOutputStream) {
    lock.lock()
    if stream == .stdout { stdoutEOF = true } else { stderrEOF = true }
    let status = childStatus
    let shouldFinish = status != nil && stdoutEOF && stderrEOF && !didFinish
    if shouldFinish { didFinish = true }
    lock.unlock()
    if shouldFinish, let status { finish(status: status) }
  }

  private func finish(status: Int32) {
    closeReaders()
    lock.lock()
    let completion = self.completion
    self.completion = nil
    lock.unlock()
    completion?(status)
  }

  private func closeReaders() {
    stdout.readabilityHandler = nil
    stderr.readabilityHandler = nil
    try? stdout.close()
    try? stderr.close()
  }
}
