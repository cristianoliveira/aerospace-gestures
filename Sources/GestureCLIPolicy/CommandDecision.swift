import GestureCore

/// Resolves a recognized gesture to an executable binding; listen/dry-run never select one.
public enum CommandDecision {
  public static func binding(
    for gesture: Gesture,
    in bindings: [Binding],
    modifiers: ModifierSample,
    dryRun: Bool
  ) -> Binding? {
    guard !dryRun, case .known(let currentModifiers) = modifiers else { return nil }
    return bindings.first {
      $0.gesture == gesture && $0.modifiers == currentModifiers
    }
  }
}
