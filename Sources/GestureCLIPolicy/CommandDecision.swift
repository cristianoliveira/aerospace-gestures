import Foundation
import GestureCore

/// Resolves a recognized gesture to an executable binding; listen/dry-run never select one.
public enum CommandDecision {
  public static func binding(
    for gesture: Gesture,
    in bindings: [Binding],
    modifiers: ModifierSample,
    dryRun: Bool,
    frontmostApp: String? = nil,
    appBindingsEnabled: Bool = true
  ) -> Binding? {
    guard !dryRun, case .known(let currentModifiers) = modifiers else { return nil }
    let matching = bindings.filter {
      $0.gesture == gesture && $0.modifiers == currentModifiers
    }
    if appBindingsEnabled, let frontmostApp,
      let scoped = matching.first(where: { $0.app == frontmostApp }) {
      return scoped
    }
    return matching.first(where: { $0.app == nil })
  }
}

/// Independent opt-in switch for app-specific bindings; generic gestures remain active.
public final class AppGesturePolicy {
  private let lock = NSLock()
  private var enabled: Bool
  private let onChange: (Bool) -> Void

  public init(enabled: Bool = true, onChange: @escaping (Bool) -> Void = { _ in }) {
    self.enabled = enabled
    self.onChange = onChange
  }
  public var isEnabled: Bool {
    lock.lock(); defer { lock.unlock() }
    return enabled
  }
  public func setEnabled(_ value: Bool) {
    lock.lock()
    guard enabled != value else { lock.unlock(); return }
    enabled = value
    lock.unlock()
    onChange(value)
  }
}
