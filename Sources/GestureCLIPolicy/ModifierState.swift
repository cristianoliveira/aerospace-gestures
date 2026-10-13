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
