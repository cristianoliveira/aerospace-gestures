import Foundation
import GestureCore

public enum AppBindingPrecedence: String, Equatable, Sendable {
  case appFirst
  case globalFirst
}

/// Resolves a recognized gesture to an executable binding; listen/dry-run never select one.
public enum CommandDecision {
  public static func binding(
    for gesture: Gesture,
    in bindings: [Binding],
    modifiers: ModifierSample,
    dryRun: Bool,
    frontmostApp: String? = nil,
    appBindingsEnabled: Bool = true,
    precedence: AppBindingPrecedence = .appFirst
  ) -> Binding? {
    guard !dryRun, case .known(let currentModifiers) = modifiers else { return nil }
    let matching = bindings.filter {
      $0.gesture == gesture && $0.modifiers == currentModifiers
    }
    let generic = matching.first(where: { $0.app == nil })
    guard appBindingsEnabled, let frontmostApp else { return generic }
    let scoped = matching.first(where: { $0.app == frontmostApp })
    switch precedence {
    case .appFirst: return scoped ?? generic
    case .globalFirst: return generic ?? scoped
    }
  }
}

/// Pins the frontmost-app sample, including an unknown sample, for one contact sequence.
public struct AppGestureFocusTracker {
  private var isActive = false
  private var pinnedApp: String?
  private var appBindingsWereEnabled = false
  private var appScopeSuppressed = false
  private var isInvalidated = false
  private var sequencePrecedence = AppBindingPrecedence.appFirst

  public init() {}

  /// A focus change after a known initial app invalidates all dispatch until full lift.
  public mutating func reset() {
    isActive = false
    pinnedApp = nil
    appBindingsWereEnabled = false
    appScopeSuppressed = false
    isInvalidated = false
    sequencePrecedence = .appFirst
  }

  public mutating func observe(
    contactCount: Int, frontmostApp: String?, appBindingsEnabled: Bool,
    precedence: AppBindingPrecedence = .appFirst
  ) -> (mayDispatch: Bool, matchingApp: String?, precedence: AppBindingPrecedence) {
    guard contactCount > 0 else {
      reset()
      return (false, nil, precedence)
    }
    if !isActive {
      isActive = true
      pinnedApp = frontmostApp
      appBindingsWereEnabled = appBindingsEnabled
      sequencePrecedence = precedence
    } else if appBindingsWereEnabled, appBindingsEnabled,
      let pinnedApp, pinnedApp != frontmostApp
    {
      isInvalidated = true
    }
    if appBindingsWereEnabled && !appBindingsEnabled {
      appScopeSuppressed = true
    }
    guard !isInvalidated else { return (false, nil, sequencePrecedence) }
    let matchingApp =
      appBindingsWereEnabled && appBindingsEnabled && !appScopeSuppressed
      ? pinnedApp : nil
    return (true, matchingApp, sequencePrecedence)
  }
}

/// Stores only the app-scoped gesture toggle in an explicit per-user defaults suite.
public struct AppGesturePreferenceStore {
  public static let suiteName = "com.aerospace-gestures"
  private static let key = "appScopedGesturesEnabled"
  private static let precedenceKey = "appBindingPrecedence"
  private let defaults: UserDefaults

  public init(defaults: UserDefaults? = UserDefaults(suiteName: suiteName)) {
    self.defaults = defaults ?? .standard
  }

  public func load() -> Bool? {
    defaults.object(forKey: Self.key) as? Bool
  }

  public func save(_ enabled: Bool) {
    defaults.set(enabled, forKey: Self.key)
  }

  public func loadPrecedence() -> AppBindingPrecedence? {
    guard let rawValue = defaults.string(forKey: Self.precedenceKey) else { return nil }
    return AppBindingPrecedence(rawValue: rawValue)
  }

  public func savePrecedence(_ precedence: AppBindingPrecedence) {
    defaults.set(precedence.rawValue, forKey: Self.precedenceKey)
  }
}

public struct AppBindingPrecedencePresentation: Equatable {
  public let isHidden: Bool
  public let appFirstIsChecked: Bool
  public let globalFirstIsChecked: Bool

  public init(hasAppScopedBindings: Bool, precedence: AppBindingPrecedence) {
    isHidden = !hasAppScopedBindings
    appFirstIsChecked = precedence == .appFirst
    globalFirstIsChecked = precedence == .globalFirst
  }
}

/// Independent opt-in switch for app-specific bindings; generic gestures remain active.
public final class AppGesturePolicy {
  private let lock = NSLock()
  private var enabled: Bool
  private var hasAppScopedBindings: Bool
  private var bindingPrecedence: AppBindingPrecedence
  private let onChange: (Bool) -> Void
  private let onPrecedenceChange: (AppBindingPrecedence) -> Void

  public init(
    enabled: Bool = true,
    hasAppScopedBindings: Bool = false,
    precedence: AppBindingPrecedence = .appFirst,
    onChange: @escaping (Bool) -> Void = { _ in },
    onPrecedenceChange: @escaping (AppBindingPrecedence) -> Void = { _ in }
  ) {
    self.enabled = enabled
    self.hasAppScopedBindings = hasAppScopedBindings
    bindingPrecedence = precedence
    self.onChange = onChange
    self.onPrecedenceChange = onPrecedenceChange
  }

  public var isEnabled: Bool {
    lock.lock()
    defer { lock.unlock() }
    return enabled
  }

  public var hasScopedBindings: Bool {
    lock.lock()
    defer { lock.unlock() }
    return hasAppScopedBindings
  }

  public var precedence: AppBindingPrecedence {
    lock.lock()
    defer { lock.unlock() }
    return bindingPrecedence
  }

  public func setPrecedence(_ value: AppBindingPrecedence) {
    lock.lock()
    guard bindingPrecedence != value else {
      lock.unlock()
      return
    }
    bindingPrecedence = value
    lock.unlock()
    onPrecedenceChange(value)
  }

  public func setHasAppScopedBindings(_ value: Bool) {
    lock.lock()
    hasAppScopedBindings = value
    lock.unlock()
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
