import Foundation

public struct InputDiagnosticsSnapshot: Equatable, Sendable {
  public let bridgeCallbackArrivals: UInt64
  public let bridgeInvalidFrameRejects: UInt64
  public let deviceSnapshotEnumerations: UInt64
  public let topologyCallbackDeliveries: UInt64
  public let deviceRegistrationCalls: UInt64
  public let deviceStopCalls: UInt64
  public let callbackGenerationExhaustions: UInt64
  public let topologyEventNotifications: UInt64
  public let topologyObserverFailures: UInt64
  /// True when IOService notifications and the main-run-loop source were installed.
  public let topologyObserverArmed: Bool
  public let topologyRebindBegins: UInt64
  public let topologyRebindEnds: UInt64
  public let deviceTopologyRebinds: UInt64
  public let deviceCountWatchdogRuns: UInt64
  public let deviceCountChanges: UInt64
  public let topologyRebindPending: Bool
  public let registeredDevices: UInt64
  public let deviceEnumerationFailures: UInt64
  public let deviceRegistrationFailures: UInt64
  public let identityGettersAvailable: Bool
  public let lastCallbackAgeSeconds: UInt64?
  public let sequenceStaleDrops: UInt64
  public let acceptedDeliveries: UInt64
  public let mainQueueScheduled: UInt64
  public let mainQueueProcessed: UInt64

  public var summary: String {
    let callbackAge = lastCallbackAgeSeconds.map(String.init) ?? "none"
    return
      "input-diagnostics snapshot_enumerations=\(deviceSnapshotEnumerations) callbacks=\(bridgeCallbackArrivals) invalid_frames=\(bridgeInvalidFrameRejects) topology_event_notifications=\(topologyEventNotifications) topology_callback_deliveries=\(topologyCallbackDeliveries) topology_observer_failures=\(topologyObserverFailures) topology_observer_armed=\(topologyObserverArmed ? 1 : 0) topology_rebind_begins=\(topologyRebindBegins) topology_rebind_ends=\(topologyRebindEnds) topology_rebinds=\(deviceTopologyRebinds) count_watchdog_runs=\(deviceCountWatchdogRuns) count_changes=\(deviceCountChanges) topology_rebind_pending=\(topologyRebindPending ? 1 : 0) register_calls=\(deviceRegistrationCalls) stop_calls=\(deviceStopCalls) registered_devices=\(registeredDevices) generation_exhaustions=\(callbackGenerationExhaustions) enumeration_failures=\(deviceEnumerationFailures) registration_failures=\(deviceRegistrationFailures) identity_getters_available=\(identityGettersAvailable ? 1 : 0) last_callback_age_s=\(callbackAge) sequence_stale_drops=\(sequenceStaleDrops) accepted_frames=\(acceptedDeliveries) main_queue_scheduled=\(mainQueueScheduled) main_queue_processed=\(mainQueueProcessed) input_state=unclassified"
  }
}
