import Foundation
import GestureCore
import MultitouchBridge

/// Owns the private bridge boundary and copies callback-owned contacts before returning.
/// Call start, refresh, and stop on the main thread. In-flight callbacks may complete after stop.
public enum MultitouchInput {
  private static let controller = MultitouchInputController(
    startTopologyObserver: {
      AGStartDeviceTopologyObserver(topologyChanged) == 0
    },
    stopTopologyObserver: { AGStopDeviceTopologyObserver() },
    startBridge: {
      guard let error = AGStart(receiveFrame) else { return nil }
      return String(cString: error)
    },
    stopBridge: { AGStop() },
    enumerateDevices: enumerateDevices,
    registerDevice: { handle, token in
      AGRegisterDevice(handle, token) == 0
    },
    unregisterDevice: { handle, token in
      AGUnregisterDevice(handle, token)
    })

  private static let topologyChanged: AGDeviceTopologyCallback = {
    controller.handleDeviceTopologyChange()
  }

  public static func start(
    onFrame: @escaping (UInt, UInt32, [Contact]) -> Void,
    onDeviceRemoved: @escaping (UInt) -> Void = { _ in }
  ) -> String? {
    controller.start(onFrame: onFrame, onDeviceRemoved: onDeviceRemoved)
  }

  public static func refreshDevices() {
    controller.refreshDevices()
  }

  public static func checkDeviceCountIfObserverUnavailable() {
    controller.checkDeviceCountIfObserverUnavailable()
  }

  public static func isDeviceRegistered(_ token: UInt) -> Bool {
    controller.isDeviceRegistered(token)
  }

  public static func stop() {
    controller.stop()
  }

  public static func diagnosticsSnapshot() -> InputDiagnosticsSnapshot {
    controller.diagnosticsSnapshot()
  }

  public static func recordMainQueueScheduled() {
    controller.recordMainQueueScheduled()
  }

  public static func recordMainQueueProcessed() {
    controller.recordMainQueueProcessed()
  }

  private static func enumerateDevices() -> InputDeviceSnapshot? {
    guard let snapshot = AGCreateDeviceSnapshot() else { return nil }
    let owner = BridgeDeviceSnapshotOwner(snapshot)
    let count = Int(AGDeviceSnapshotCount(snapshot))
    var devices: [InputDeviceDescriptor] = []
    devices.reserveCapacity(count)

    for index in 0..<count {
      guard let identity = AGDeviceSnapshotIdentityAtIndex(snapshot, index) else { return nil }
      devices.append(
        InputDeviceDescriptor(
          identity: String(cString: identity),
          handle: UInt(AGDeviceSnapshotHandleAtIndex(snapshot, index))))
    }

    return InputDeviceSnapshot(
      devices: devices,
      supportsStableIdentity: AGDeviceSnapshotSupportsStableIdentity(snapshot) != 0,
      lifetime: owner)
  }

  private static let receiveFrame: AGFrameCallback = { token, frame, raw, count in
    let contacts = (0..<Int(count)).map { index -> Contact in
      let point = raw![index]
      return Contact(id: Int(point.id), x: Double(point.x), y: Double(point.y))
    }
    controller.receive(device: UInt(token), frame: frame, contacts: contacts)
  }
}

private final class BridgeDeviceSnapshotOwner {
  private let snapshot: OpaquePointer

  init(_ snapshot: OpaquePointer) {
    self.snapshot = snapshot
  }

  deinit {
    AGReleaseDeviceSnapshot(snapshot)
  }
}

final class MultitouchInputController {
  private enum ReconciliationReason {
    case startup
    case topologyEvent
    case topologyRecoveryRetry
    case observerUnavailableCountChange

    var forcesRebind: Bool {
      switch self {
      case .startup:
        return false
      case .topologyEvent, .topologyRecoveryRetry, .observerUnavailableCountChange:
        return true
      }
    }
  }

  private enum SnapshotSource {
    case enumerate
    case provided(InputDeviceSnapshot)
  }

  private let startTopologyObserver: () -> Bool
  private let stopTopologyObserver: () -> Void
  private let startBridge: () -> String?
  private let stopBridge: () -> Void
  private let enumerateDevices: () -> InputDeviceSnapshot?
  private let registerDevice: (UInt, UInt) -> Bool
  private let unregisterDevice: (UInt, UInt) -> Void
  private let lifecycleLock = NSRecursiveLock()
  private let handlerLock = NSLock()
  // Keep sequence validation and handler submission atomic across concurrent callbacks.
  private let frameDeliveryLock = NSLock()
  private let diagnosticsLock = NSLock()
  private var frameHandler: ((UInt, UInt32, [Contact]) -> Void)?
  private var deviceRemovedHandler: ((UInt) -> Void)?
  private(set) var registry = DeviceRegistrationRegistry()
  private var registrationSnapshots: [UInt: InputDeviceSnapshot] = [:]
  private var activeTokens: Set<UInt> = []
  private var lastFrameByDevice: [UInt: UInt32] = [:]
  private var isStarted = false
  private var identityGettersAvailable = false
  private var lastKnownDeviceCount: Int?
  private var deviceCountWatchdogRuns: UInt64 = 0
  private var deviceCountChanges: UInt64 = 0
  private var sequenceStaleDrops: UInt64 = 0
  private var acceptedDeliveries: UInt64 = 0
  private var deviceEnumerationFailures: UInt64 = 0
  private var deviceRegistrationFailures: UInt64 = 0
  private var mainQueueScheduled: UInt64 = 0
  private var mainQueueProcessed: UInt64 = 0
  private var deviceTopologyObserverArmed = false
  private var topologyRebindBegins: UInt64 = 0
  private var topologyRebindEnds: UInt64 = 0
  private var deviceTopologyRebinds: UInt64 = 0
  private var topologyEventRebindAttempts: UInt64 = 0
  private var topologyRetryRebindAttempts: UInt64 = 0
  private var countChangeRebindAttempts: UInt64 = 0
  private var forceTopologyRebindPending = false
  private var pendingRegistrationRetries: [String: (InputDeviceDescriptor, InputDeviceSnapshot)] =
    [:]
  private var registrationRetryAttempts: [String: Int] = [:]
  private var exhaustedRegistrationRetries: Set<String> = []
  private let maximumRegistrationRetries = 3

  init(
    startTopologyObserver: @escaping () -> Bool = { false },
    stopTopologyObserver: @escaping () -> Void = {},
    startBridge: @escaping () -> String?,
    stopBridge: @escaping () -> Void,
    enumerateDevices: @escaping () -> InputDeviceSnapshot? = {
      InputDeviceSnapshot(devices: [])
    },
    registerDevice: @escaping (UInt, UInt) -> Bool = { _, _ in true },
    unregisterDevice: @escaping (UInt, UInt) -> Void = { _, _ in }
  ) {
    self.startTopologyObserver = startTopologyObserver
    self.stopTopologyObserver = stopTopologyObserver
    self.startBridge = startBridge
    self.stopBridge = stopBridge
    self.enumerateDevices = enumerateDevices
    self.registerDevice = registerDevice
    self.unregisterDevice = unregisterDevice
  }

  func start(
    onFrame: @escaping (UInt, UInt32, [Contact]) -> Void,
    onDeviceRemoved: @escaping (UInt) -> Void = { _ in }
  ) -> String? {
    lifecycleLock.lock()
    defer { lifecycleLock.unlock() }

    guard !isStarted else { return "Multitouch listener already started" }
    clearPendingRecovery()
    handlerLock.lock()
    frameHandler = onFrame
    deviceRemovedHandler = onDeviceRemoved
    handlerLock.unlock()

    frameDeliveryLock.lock()
    activeTokens.removeAll(keepingCapacity: true)
    lastFrameByDevice.removeAll(keepingCapacity: true)
    frameDeliveryLock.unlock()

    let topologyObserverArmed = startTopologyObserver()
    guard let error = startBridge() else {
      isStarted = true
      diagnosticsLock.lock()
      identityGettersAvailable = true
      self.deviceTopologyObserverArmed = topologyObserverArmed
      diagnosticsLock.unlock()
      refreshDevicesLocked(for: .startup)
      return nil
    }

    stopTopologyObserver()
    diagnosticsLock.lock()
    deviceTopologyObserverArmed = false
    diagnosticsLock.unlock()
    clearHandlers()
    return error
  }

  func refreshDevices() {
    lifecycleLock.lock()
    defer { lifecycleLock.unlock() }
    guard isStarted else { return }
    if forceTopologyRebindPending {
      refreshDevicesLocked(for: .topologyRecoveryRetry)
      return
    }
    retryPendingUnstableRegistrations()
  }

  func checkDeviceCountIfObserverUnavailable() {
    lifecycleLock.lock()
    defer { lifecycleLock.unlock() }
    guard isStarted else { return }

    diagnosticsLock.lock()
    let observerArmed = deviceTopologyObserverArmed
    if !observerArmed { deviceCountWatchdogRuns &+= 1 }
    diagnosticsLock.unlock()
    guard !observerArmed else { return }

    guard let snapshot = enumerateDevices() else {
      diagnosticsLock.lock()
      deviceEnumerationFailures &+= 1
      diagnosticsLock.unlock()
      return
    }
    guard let previousCount = lastKnownDeviceCount else {
      lastKnownDeviceCount = snapshot.devices.count
      return
    }
    guard snapshot.devices.count != previousCount else { return }

    diagnosticsLock.lock()
    deviceCountChanges &+= 1
    diagnosticsLock.unlock()
    refreshDevicesLocked(
      for: .observerUnavailableCountChange,
      using: .provided(snapshot))
  }

  func handleDeviceTopologyChange() {
    lifecycleLock.lock()
    defer { lifecycleLock.unlock() }
    guard isStarted else { return }
    forceTopologyRebindPending = true
    refreshDevicesLocked(for: .topologyEvent)
  }

  func stop() {
    lifecycleLock.lock()
    defer { lifecycleLock.unlock() }
    guard isStarted else { return }
    isStarted = false
    clearPendingRecovery()
    stopTopologyObserver()
    diagnosticsLock.lock()
    deviceTopologyObserverArmed = false
    diagnosticsLock.unlock()
    handlerLock.lock()
    let removedHandler = deviceRemovedHandler
    frameHandler = nil
    deviceRemovedHandler = nil
    handlerLock.unlock()

    let removed = registry.removeAll()
    for registration in removed {
      deactivate(registration.token)
      unregisterDevice(registration.descriptor.handle, registration.token)
      removedHandler?(registration.token)
      registrationSnapshots.removeValue(forKey: registration.token)
    }
    stopBridge()
  }

  func receive(device: UInt, frame: UInt32, contacts: [Contact]) {
    handlerLock.lock()
    let handler = frameHandler
    handlerLock.unlock()
    guard let handler else { return }

    frameDeliveryLock.lock()
    defer { frameDeliveryLock.unlock() }
    guard activeTokens.contains(device) else { return }
    if let previousFrame = lastFrameByDevice[device], !Self.isNewer(frame, than: previousFrame) {
      diagnosticsLock.lock()
      sequenceStaleDrops &+= 1
      diagnosticsLock.unlock()
      return
    }
    lastFrameByDevice[device] = frame
    diagnosticsLock.lock()
    acceptedDeliveries &+= 1
    diagnosticsLock.unlock()
    handler(device, frame, contacts)
  }

  func isDeviceRegistered(_ token: UInt) -> Bool {
    frameDeliveryLock.lock()
    defer { frameDeliveryLock.unlock() }
    return activeTokens.contains(token)
  }

  func recordMainQueueScheduled() {
    diagnosticsLock.lock()
    mainQueueScheduled &+= 1
    diagnosticsLock.unlock()
  }

  func recordMainQueueProcessed() {
    diagnosticsLock.lock()
    mainQueueProcessed &+= 1
    diagnosticsLock.unlock()
  }

  func diagnosticsSnapshot() -> InputDiagnosticsSnapshot {
    lifecycleLock.lock()
    let topologyRebindPending =
      forceTopologyRebindPending || !pendingRegistrationRetries.isEmpty
    lifecycleLock.unlock()

    diagnosticsLock.lock()
    let staleDrops = sequenceStaleDrops
    let acceptedDeliveries = acceptedDeliveries
    let enumerationFailures = deviceEnumerationFailures
    let registrationFailures = deviceRegistrationFailures
    let hasIdentityGetters = identityGettersAvailable
    let scheduled = mainQueueScheduled
    let processed = mainQueueProcessed
    let topologyObserverArmed = deviceTopologyObserverArmed
    let rebindBegins = topologyRebindBegins
    let rebindEnds = topologyRebindEnds
    let topologyRebinds = deviceTopologyRebinds
    let eventRebindAttempts = topologyEventRebindAttempts
    let retryRebindAttempts = topologyRetryRebindAttempts
    let countChangeRebindAttempts = self.countChangeRebindAttempts
    let countWatchdogRuns = deviceCountWatchdogRuns
    let deviceCountChanges = deviceCountChanges
    diagnosticsLock.unlock()

    var bridge = AGBridgeDiagnostics()
    AGReadBridgeDiagnostics(&bridge)
    let callbackAge =
      bridge.last_callback_age_nanoseconds == UInt64.max
      ? nil
      : bridge.last_callback_age_nanoseconds / 1_000_000_000
    return InputDiagnosticsSnapshot(
      bridgeCallbackArrivals: bridge.callback_arrivals,
      bridgeInvalidFrameRejects: bridge.invalid_frame_rejects,
      deviceSnapshotEnumerations: bridge.device_snapshot_enumerations,
      deviceSnapshotSuccesses: bridge.device_snapshot_successes,
      deviceSnapshotLastCount: bridge.device_snapshot_successes == 0
        ? nil
        : bridge.device_snapshot_last_count,
      topologyPublishedServices: bridge.iohid_published_services,
      topologyTerminatedServices: bridge.iohid_terminated_services,
      topologyTrackedTerminations: bridge.tracked_touchpad_terminations,
      topologyTouchPadMatches: bridge.touchpad_matches,
      topologyUsagePairNonmatches: bridge.usage_pairs_nonmatches,
      topologyUsagePairInvalid: bridge.usage_pairs_invalid,
      topologyCallbackDeliveries: bridge.topology_callback_deliveries,
      deviceRegistrationCalls: bridge.device_registration_calls,
      deviceStopCalls: bridge.device_stop_calls,
      callbackGenerationExhaustions: bridge.callback_generation_exhaustions,
      topologyEventNotifications: bridge.topology_event_notifications,
      topologyObserverFailures: bridge.topology_observer_failures,
      topologyObserverArmed: topologyObserverArmed,
      topologyRebindBegins: rebindBegins,
      topologyRebindEnds: rebindEnds,
      deviceTopologyRebinds: topologyRebinds,
      topologyEventRebindAttempts: eventRebindAttempts,
      topologyRetryRebindAttempts: retryRebindAttempts,
      countChangeRebindAttempts: countChangeRebindAttempts,
      deviceCountWatchdogRuns: countWatchdogRuns,
      deviceCountChanges: deviceCountChanges,
      topologyRebindPending: topologyRebindPending,
      registeredDevices: bridge.registered_devices,
      deviceEnumerationFailures: enumerationFailures,
      deviceRegistrationFailures: registrationFailures,
      identityGettersAvailable: hasIdentityGetters,
      lastCallbackAgeSeconds: callbackAge,
      sequenceStaleDrops: staleDrops,
      acceptedDeliveries: acceptedDeliveries,
      mainQueueScheduled: scheduled,
      mainQueueProcessed: processed)
  }

  @discardableResult
  private func refreshDevicesLocked(
    for reason: ReconciliationReason,
    using snapshotSource: SnapshotSource = .enumerate
  ) -> Bool {
    let forceRebind = reason.forcesRebind
    if forceRebind {
      diagnosticsLock.lock()
      switch reason {
      case .startup:
        break
      case .topologyEvent:
        topologyEventRebindAttempts &+= 1
      case .topologyRecoveryRetry:
        topologyRetryRebindAttempts &+= 1
      case .observerUnavailableCountChange:
        countChangeRebindAttempts &+= 1
      }
      topologyRebindBegins &+= 1
      diagnosticsLock.unlock()
    }
    defer {
      if forceRebind {
        diagnosticsLock.lock()
        topologyRebindEnds &+= 1
        diagnosticsLock.unlock()
      }
    }
    let snapshot: InputDeviceSnapshot?
    switch snapshotSource {
    case .enumerate:
      snapshot = enumerateDevices()
    case .provided(let providedSnapshot):
      snapshot = providedSnapshot
    }
    guard let snapshot else {
      diagnosticsLock.lock()
      deviceEnumerationFailures &+= 1
      diagnosticsLock.unlock()
      return false
    }

    let discoveredIdentities = Set(snapshot.devices.map(\.identity))

    let changes: DeviceReconciliation
    do {
      changes = try registry.reconcile(snapshot.devices, forceRebind: forceRebind)
    } catch {
      diagnosticsLock.lock()
      deviceEnumerationFailures &+= 1
      diagnosticsLock.unlock()
      return false
    }

    lastKnownDeviceCount = snapshot.devices.count
    diagnosticsLock.lock()
    identityGettersAvailable = snapshot.supportsStableIdentity
    diagnosticsLock.unlock()

    if forceRebind {
      pendingRegistrationRetries.removeAll()
      registrationRetryAttempts.removeAll()
      exhaustedRegistrationRetries.removeAll()
    }
    let trackedRetryIdentities = Set(pendingRegistrationRetries.keys)
      .union(registrationRetryAttempts.keys)
      .union(exhaustedRegistrationRetries)
    for identity in trackedRetryIdentities where !discoveredIdentities.contains(identity) {
      clearRegistrationRetry(for: identity)
    }

    for registration in changes.removed {
      deactivate(registration.token)
      unregisterDevice(registration.descriptor.handle, registration.token)
      deviceRemovedHandler?(registration.token)
      registrationSnapshots.removeValue(forKey: registration.token)
      clearRegistrationRetry(for: registration.descriptor.identity)
    }

    for registration in changes.added {
      let identity = registration.descriptor.identity
      guard !exhaustedRegistrationRetries.contains(identity) else {
        registry.remove(registration)
        continue
      }
      registrationSnapshots[registration.token] = snapshot
      activate(registration.token)
      if registerDevice(registration.descriptor.handle, registration.token) {
        clearRegistrationRetry(for: identity)
        continue
      }

      deactivate(registration.token)
      registry.remove(registration)
      registrationSnapshots.removeValue(forKey: registration.token)
      recordRegistrationFailure(registration, snapshot: snapshot)
    }

    if forceRebind {
      forceTopologyRebindPending = false
      diagnosticsLock.lock()
      deviceTopologyRebinds &+= 1
      diagnosticsLock.unlock()
    }
    return true
  }

  private func retryPendingUnstableRegistrations() {
    for identity in pendingRegistrationRetries.keys.sorted() {
      guard let (descriptor, snapshot) = pendingRegistrationRetries[identity] else { continue }
      guard let registration = registry.createRegistration(for: descriptor) else {
        clearRegistrationRetry(for: identity)
        continue
      }

      registrationSnapshots[registration.token] = snapshot
      activate(registration.token)
      if registerDevice(descriptor.handle, registration.token) {
        clearRegistrationRetry(for: identity)
        continue
      }

      deactivate(registration.token)
      registry.remove(registration)
      registrationSnapshots.removeValue(forKey: registration.token)
      recordRegistrationFailure(registration, snapshot: snapshot)
    }
  }

  private func recordRegistrationFailure(
    _ registration: DeviceRegistration,
    snapshot: InputDeviceSnapshot
  ) {
    let identity = registration.descriptor.identity
    let attempts = (registrationRetryAttempts[identity] ?? 0) + 1
    registrationRetryAttempts[identity] = attempts
    if attempts >= maximumRegistrationRetries {
      pendingRegistrationRetries.removeValue(forKey: identity)
      exhaustedRegistrationRetries.insert(identity)
    } else {
      pendingRegistrationRetries[identity] = (registration.descriptor, snapshot)
    }
    diagnosticsLock.lock()
    deviceRegistrationFailures &+= 1
    diagnosticsLock.unlock()
  }

  private func clearRegistrationRetry(for identity: String) {
    pendingRegistrationRetries.removeValue(forKey: identity)
    registrationRetryAttempts.removeValue(forKey: identity)
    exhaustedRegistrationRetries.remove(identity)
  }

  private func clearPendingRecovery() {
    forceTopologyRebindPending = false
    pendingRegistrationRetries.removeAll()
    registrationRetryAttempts.removeAll()
    exhaustedRegistrationRetries.removeAll()
  }

  private func activate(_ token: UInt) {
    frameDeliveryLock.lock()
    activeTokens.insert(token)
    frameDeliveryLock.unlock()
  }

  private func deactivate(_ token: UInt) {
    frameDeliveryLock.lock()
    activeTokens.remove(token)
    lastFrameByDevice.removeValue(forKey: token)
    frameDeliveryLock.unlock()
  }

  private func clearHandlers() {
    handlerLock.lock()
    frameHandler = nil
    deviceRemovedHandler = nil
    handlerLock.unlock()
  }

  private static func isNewer(_ frame: UInt32, than previousFrame: UInt32) -> Bool {
    // Unsigned subtraction handles wrap; the half-range test rejects stale frames.
    let distance = frame &- previousFrame
    return distance > 0 && distance < 0x8000_0000
  }
}
