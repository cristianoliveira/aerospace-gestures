import Foundation
import GestureCore

public enum GestureExecutionMode: Equatable {
  case run
  case listen
  case dryRun
}

public enum GestureActionState: Equatable {
  case enabled
  case paused
  case unavailable
}

/// Identifies a frame's policy generation and device across asynchronous main-queue delivery.
public struct GestureFrameToken: Equatable {
  fileprivate let generation: UInt64
  fileprivate let device: UInt
}

/// Thread-safe command gate. UI transitions and gesture decisions are still performed on main.
public final class GestureActionPolicy {
  private let mode: GestureExecutionMode
  private let lock = NSLock()
  private var actionsEnabled = true
  private var generation: UInt64 = 0
  private var activeDevices: Set<UInt> = []
  private var devicesRequiringLift: Set<UInt> = []

  public init(mode: GestureExecutionMode) {
    self.mode = mode
  }

  public var state: GestureActionState {
    lock.lock()
    defer { lock.unlock() }
    guard mode == .run else { return .unavailable }
    return actionsEnabled ? .enabled : .paused
  }

  public var showsMenuBarControl: Bool {
    mode == .run
  }

  /// Changes only normal run mode; a pause transition never terminates an active command.
  public func setActionsEnabled(_ enabled: Bool) {
    lock.lock()
    defer { lock.unlock() }
    guard mode == .run, actionsEnabled != enabled else { return }

    actionsEnabled = enabled
    generation &+= 1
    devicesRequiringLift.formUnion(activeDevices)
  }

  /// Captures the current policy generation before a frame is queued for main-thread processing.
  public func captureFrame(device: UInt, contactCount: Int) -> GestureFrameToken {
    lock.lock()
    defer { lock.unlock() }

    if contactCount == 0 {
      activeDevices.remove(device)
      devicesRequiringLift.remove(device)
    } else {
      activeDevices.insert(device)
    }
    return GestureFrameToken(generation: generation, device: device)
  }

  public func isCurrent(_ token: GestureFrameToken) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return token.generation == generation
  }

  public func mayDispatch(_ gesture: Gesture, from token: GestureFrameToken) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    return mode == .run && actionsEnabled && token.generation == generation
      && !devicesRequiringLift.contains(token.device)
  }
}
