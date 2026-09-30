import Foundation
import GestureCore

public struct ConfigurationReloadToken: Equatable, Sendable {
  fileprivate let id: UInt64
}

public enum ConfigurationReloadState: Equatable {
  case unavailable
  case ready
  case loading
  case succeeded
  case failed(String)
}

public enum ConfigurationReloadResult: Sendable {
  case success(Configuration)
  case failure(String)
}

/// Owns the active immutable config and accepts at most one validated replacement at a time.
public final class ConfigurationReloadPolicy {
  private let mode: GestureExecutionMode
  private let lock = NSLock()
  private var configuration: Configuration?
  private var activeToken: ConfigurationReloadToken?
  private var nextToken: UInt64 = 0
  private var reloadState: ConfigurationReloadState

  public init(initialConfiguration: Configuration?, mode: GestureExecutionMode) {
    self.mode = mode
    configuration = initialConfiguration
    reloadState = mode == .run && initialConfiguration != nil ? .ready : .unavailable
  }

  public var canReload: Bool {
    lock.lock()
    defer { lock.unlock() }
    return mode == .run && configuration != nil
  }

  public var activeConfiguration: Configuration? {
    lock.lock()
    defer { lock.unlock() }
    return configuration
  }

  public var state: ConfigurationReloadState {
    lock.lock()
    defer { lock.unlock() }
    return reloadState
  }

  public func beginReload() -> ConfigurationReloadToken? {
    lock.lock()
    defer { lock.unlock() }
    guard mode == .run, configuration != nil, activeToken == nil else { return nil }

    nextToken &+= 1
    let token = ConfigurationReloadToken(id: nextToken)
    activeToken = token
    reloadState = .loading
    return token
  }

  /// Failure changes only presentation state; the previously active configuration remains intact.
  @discardableResult
  public func completeReload(
    _ token: ConfigurationReloadToken, with result: ConfigurationReloadResult
  ) -> Bool {
    lock.lock()
    defer { lock.unlock() }
    guard activeToken == token else { return false }

    activeToken = nil
    switch result {
    case .success(let replacement):
      configuration = replacement
      reloadState = .succeeded
    case .failure(let message):
      reloadState = .failed(message)
    }
    return true
  }
}

public struct ConfigurationReloadPresentation: Equatable {
  public let reloadIsEnabled: Bool
  public let feedbackMessage: String?

  public init(state: ConfigurationReloadState, canReload: Bool) {
    reloadIsEnabled = canReload && state != .loading
    switch state {
    case .unavailable, .ready:
      feedbackMessage = nil
    case .loading:
      feedbackMessage = "Reloading configuration…"
    case .succeeded:
      feedbackMessage = "Configuration reloaded"
    case .failed(let message):
      feedbackMessage = "Reload failed: \(message)"
    }
  }
}
