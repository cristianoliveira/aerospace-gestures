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
      let scoped = matching.first(where: { $0.app == frontmostApp })
    {
      return scoped
    }
    return matching.first(where: { $0.app == nil })
  }
}

/// Pins the frontmost-app sample, including an unknown sample, for one contact sequence.
public struct AppGestureFocusTracker {
  private var isActive = false
  private var pinnedApp: String?
  private var appBindingsWereEnabled = false
  private var appScopeSuppressed = false
  private var isInvalidated = false

  public init() {}

  /// A focus change after a known initial app invalidates all dispatch until full lift.
  public mutating func observe(
    contactCount: Int, frontmostApp: String?, appBindingsEnabled: Bool
  ) -> (mayDispatch: Bool, matchingApp: String?) {
    guard contactCount > 0 else {
      isActive = false
      pinnedApp = nil
      appBindingsWereEnabled = false
      appScopeSuppressed = false
      isInvalidated = false
      return (false, nil)
    }
    if !isActive {
      isActive = true
      pinnedApp = frontmostApp
      appBindingsWereEnabled = appBindingsEnabled
    } else if appBindingsWereEnabled, appBindingsEnabled,
      let pinnedApp, pinnedApp != frontmostApp
    {
      isInvalidated = true
    }
    if appBindingsWereEnabled && !appBindingsEnabled {
      appScopeSuppressed = true
    }
    guard !isInvalidated else { return (false, nil) }
    let matchingApp =
      appBindingsWereEnabled && appBindingsEnabled && !appScopeSuppressed
      ? pinnedApp : nil
    return (true, matchingApp)
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
    lock.lock()
    defer { lock.unlock() }
    return enabled
  }
  public func setEnabled(_ value: Bool) {
    lock.lock()
    guard enabled != value else {
      lock.unlock()
      return
    }
    enabled = value
    lock.unlock()
    onChange(value)
  }
}
