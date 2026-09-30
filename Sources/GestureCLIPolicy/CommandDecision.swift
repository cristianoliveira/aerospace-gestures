import GestureCore

/// Resolves a recognized gesture to an executable binding; listen/dry-run never select one.
public enum CommandDecision {
    public static func binding(for gesture: Gesture, in bindings: [Binding], dryRun: Bool) -> Binding? {
        guard !dryRun else { return nil }
        return bindings.first { $0.gesture == gesture }
    }
}
