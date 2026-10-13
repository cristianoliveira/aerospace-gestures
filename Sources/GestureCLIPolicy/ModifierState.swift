import GestureCore

public enum ModifierSample: Equatable, Sendable {
  case known(ModifierSet)
  case unknown

  public var displayName: String {
    switch self {
    case .known(let modifiers): return modifiers.displayName
    case .unknown: return "modifier state unknown"
    }
  }
}

public protocol ModifierStateSampling: Sendable {
  func sample() -> ModifierSample
}

/// Pins one exact modifier set to each device's active contact sequence.
public struct ModifierSequenceTracker {
  private enum State {
    case active(ModifierSet)
    case cancelled
  }

  private var states: [UInt: State] = [:]

  public init() {}

  /// Returns nil on full lift, the latched set while stable, or unknown after invalidation.
  public mutating func observe(
    device: UInt,
    contactCount: Int,
    sample: ModifierSample
  ) -> ModifierSample? {
    guard contactCount > 0 else {
      states.removeValue(forKey: device)
      return nil
    }

    guard let state = states[device] else {
      guard case .known(let modifiers) = sample else {
        states[device] = .cancelled
        return .unknown
      }
      states[device] = .active(modifiers)
      return .known(modifiers)
    }

    switch state {
    case .active(let latchedModifiers):
      guard case .known(let currentModifiers) = sample,
        currentModifiers == latchedModifiers
      else {
        states[device] = .cancelled
        return .unknown
      }
      return .known(latchedModifiers)
    case .cancelled:
      return .unknown
    }
  }
}
