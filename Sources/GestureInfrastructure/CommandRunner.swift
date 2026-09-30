import Darwin
import Foundation
import GestureCore

/// Main-thread runner. One child at a time; busy gestures are dropped, never queued.
public final class CommandRunner {
  private var active: Process?
  private var stopCompletion: (() -> Void)?
  private let timeout: TimeInterval
  public init(timeout: TimeInterval = 5) { self.timeout = timeout }

  @discardableResult
  public func run(_ command: [String], completion: @escaping (String) -> Void) -> Bool {
    guard active == nil else { return false }
    guard let executable = command.first else {
      completion("Empty command")
      return false
    }
    let child = Process()
    child.executableURL = URL(fileURLWithPath: executable)
    child.arguments = Array(command.dropFirst())
    child.standardInput = FileHandle.nullDevice
    // Avoid collecting command output or secrets in gesture logs.
    child.standardOutput = FileHandle.nullDevice
    child.standardError = FileHandle.nullDevice
    child.terminationHandler = { [weak self] process in
      DispatchQueue.main.async {
        guard let self, self.active === process else { return }
        self.active = nil
        completion("Command exited with status \(process.terminationStatus)")
        let stopCompletion = self.stopCompletion
        self.stopCompletion = nil
        stopCompletion?()
      }
    }
    do {
      try child.run()
      active = child
    } catch {
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

  private func terminate(_ child: Process) {
    child.terminate()
    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self, weak child] in
      guard let child, self?.active === child, child.isRunning else { return }
      kill(child.processIdentifier, SIGKILL)
    }
  }
}
