public enum GestureModifier: String, CaseIterable, Hashable, Sendable {
  case command, option, control, shift

  public var displayName: String {
    switch self {
    case .command: return "Command"
    case .option: return "Option"
    case .control: return "Control"
    case .shift: return "Shift"
    }
  }
}

public struct ModifierSet: Hashable, Sendable {
  private let values: Set<GestureModifier>

  public init(_ modifiers: [GestureModifier] = []) {
    values = Set(modifiers)
  }

  public static let none = ModifierSet()

  public func contains(_ modifier: GestureModifier) -> Bool {
    values.contains(modifier)
  }

  public var displayName: String {
    let names = GestureModifier.allCases.filter(contains).map(\.displayName)
    return names.isEmpty ? "no modifiers" : names.joined(separator: "+")
  }
}
