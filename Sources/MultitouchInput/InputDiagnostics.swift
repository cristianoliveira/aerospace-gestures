import Foundation

public struct InputDiagnosticsSnapshot: Equatable, Sendable {
  public let bridgeCallbackArrivals: UInt64
  public let bridgeInvalidFrameRejects: UInt64
  public let deviceRegistrationCalls: UInt64
  public let deviceStopCalls: UInt64
  public let registeredDevices: UInt64
  public let lastCallbackAgeSeconds: UInt64?
  public let sequenceStaleDrops: UInt64
  public let acceptedDeliveries: UInt64
  public let mainQueueScheduled: UInt64
  public let mainQueueProcessed: UInt64

  public var summary: String {
    let callbackAge = lastCallbackAgeSeconds.map(String.init) ?? "none"
    return
      "input-diagnostics callbacks=\(bridgeCallbackArrivals) invalid_frames=\(bridgeInvalidFrameRejects) register_calls=\(deviceRegistrationCalls) stop_calls=\(deviceStopCalls) registered_devices=\(registeredDevices) last_callback_age_s=\(callbackAge) sequence_stale_drops=\(sequenceStaleDrops) accepted_deliveries=\(acceptedDeliveries) main_queue_scheduled=\(mainQueueScheduled) main_queue_processed=\(mainQueueProcessed) input_state=unclassified"
  }
}
