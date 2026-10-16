import XCTest

@testable import MultitouchInput

final class InputDiagnosticsTests: XCTestCase {
  func testSummaryUsesOnlyAggregateCountersAndKeepsIdleUnclassified() {
    let snapshot = InputDiagnosticsSnapshot(
      bridgeCallbackArrivals: 0,
      bridgeInvalidFrameRejects: 0,
      deviceSnapshotEnumerations: 0,
      deviceSnapshotSuccesses: 0,
      deviceSnapshotLastCount: nil,
      topologyPublishedServices: 0,
      topologyTerminatedServices: 0,
      topologyTrackedTerminations: 0,
      topologyTouchPadMatches: 0,
      topologyUsagePairNonmatches: 0,
      topologyUsagePairInvalid: 0,
      topologyCallbackDeliveries: 0,
      deviceRegistrationCalls: 0,
      deviceStopCalls: 0,
      callbackGenerationExhaustions: 0,
      topologyEventNotifications: 0,
      topologyObserverFailures: 0,
      topologyObserverArmed: false,
      topologyRebindBegins: 0,
      topologyRebindEnds: 0,
      deviceTopologyRebinds: 0,
      topologyEventRebindAttempts: 0,
      topologyRetryRebindAttempts: 0,
      deferredTopologyRebindAttempts: 0,
      countChangeRebindAttempts: 0,
      deviceCountWatchdogRuns: 0,
      deviceCountChanges: 0,
      topologyRebindPending: false,
      registeredDevices: 0,
      deviceEnumerationFailures: 0,
      deviceRegistrationFailures: 0,
      identityGettersAvailable: false,
      lastCallbackAgeSeconds: nil,
      sequenceStaleDrops: 0,
      acceptedDeliveries: 0,
      mainQueueScheduled: 0,
      mainQueueProcessed: 0)

    XCTAssertEqual(
      snapshot.summary,
      "input-diagnostics snapshot_enumerations=0 callbacks=0 invalid_frames=0 topology_event_notifications=0 topology_callback_deliveries=0 topology_observer_failures=0 topology_observer_armed=0 topology_rebind_begins=0 topology_rebind_ends=0 topology_rebinds=0 count_watchdog_runs=0 count_changes=0 topology_rebind_pending=0 register_calls=0 stop_calls=0 registered_devices=0 generation_exhaustions=0 enumeration_failures=0 registration_failures=0 identity_getters_available=0 last_callback_age_s=none sequence_stale_drops=0 accepted_frames=0 main_queue_scheduled=0 main_queue_processed=0 input_state=unclassified"
    )
    XCTAssertEqual(
      snapshot.reconnectDiagnosticsSummary,
      "\(snapshot.summary) snapshot_successes=0 snapshot_last_count=none iohid_published_services=0 iohid_terminated_services=0 touchpad_matches=0 usage_pairs_nonmatches=0 usage_pairs_invalid=0 tracked_touchpad_terminations=0 rebind_event_attempts=0 rebind_retry_attempts=0 rebind_deferred_count_attempts=0 rebind_count_change_attempts=0"
    )
  }

  func testSummaryFormatsOnlyAggregateCountsAndCallbackAge() {
    let snapshot = InputDiagnosticsSnapshot(
      bridgeCallbackArrivals: 12,
      bridgeInvalidFrameRejects: 2,
      deviceSnapshotEnumerations: 27,
      deviceSnapshotSuccesses: 26,
      deviceSnapshotLastCount: 0,
      topologyPublishedServices: 5,
      topologyTerminatedServices: 4,
      topologyTrackedTerminations: 2,
      topologyTouchPadMatches: 3,
      topologyUsagePairNonmatches: 1,
      topologyUsagePairInvalid: 1,
      topologyCallbackDeliveries: 3,
      deviceRegistrationCalls: 3,
      deviceStopCalls: 1,
      callbackGenerationExhaustions: 2,
      topologyEventNotifications: 8,
      topologyObserverFailures: 1,
      topologyObserverArmed: true,
      topologyRebindBegins: 4,
      topologyRebindEnds: 4,
      deviceTopologyRebinds: 2,
      topologyEventRebindAttempts: 2,
      topologyRetryRebindAttempts: 1,
      deferredTopologyRebindAttempts: 3,
      countChangeRebindAttempts: 1,
      deviceCountWatchdogRuns: 3,
      deviceCountChanges: 1,
      topologyRebindPending: true,
      registeredDevices: 2,
      deviceEnumerationFailures: 3,
      deviceRegistrationFailures: 1,
      identityGettersAvailable: true,
      lastCallbackAgeSeconds: 3456,
      sequenceStaleDrops: 4,
      acceptedDeliveries: 6,
      mainQueueScheduled: 6,
      mainQueueProcessed: 5)

    XCTAssertEqual(
      snapshot.summary,
      "input-diagnostics snapshot_enumerations=27 callbacks=12 invalid_frames=2 topology_event_notifications=8 topology_callback_deliveries=3 topology_observer_failures=1 topology_observer_armed=1 topology_rebind_begins=4 topology_rebind_ends=4 topology_rebinds=2 count_watchdog_runs=3 count_changes=1 topology_rebind_pending=1 register_calls=3 stop_calls=1 registered_devices=2 generation_exhaustions=2 enumeration_failures=3 registration_failures=1 identity_getters_available=1 last_callback_age_s=3456 sequence_stale_drops=4 accepted_frames=6 main_queue_scheduled=6 main_queue_processed=5 input_state=unclassified"
    )
    XCTAssertEqual(
      snapshot.reconnectDiagnosticsSummary,
      "\(snapshot.summary) snapshot_successes=26 snapshot_last_count=0 iohid_published_services=5 iohid_terminated_services=4 touchpad_matches=3 usage_pairs_nonmatches=1 usage_pairs_invalid=1 tracked_touchpad_terminations=2 rebind_event_attempts=2 rebind_retry_attempts=1 rebind_deferred_count_attempts=3 rebind_count_change_attempts=1"
    )
  }

  func testNeverObservedBridgeCallbackHasNoAgeAndNoActiveDevices() {
    let input = MultitouchInputController(startBridge: { nil }, stopBridge: {})
    let snapshot = input.diagnosticsSnapshot()

    XCTAssertEqual(snapshot.bridgeCallbackArrivals, 0)
    XCTAssertEqual(snapshot.bridgeInvalidFrameRejects, 0)
    XCTAssertEqual(snapshot.registeredDevices, 0)
    XCTAssertNil(snapshot.lastCallbackAgeSeconds)
  }

  func testControllerCountsAcceptedAndStaleFrameBoundaries() {
    let input = MultitouchInputController(
      startBridge: { nil },
      stopBridge: {},
      enumerateDevices: {
        InputDeviceSnapshot(devices: [InputDeviceDescriptor(identity: "test-device", handle: 7)])
      })
    XCTAssertNil(input.start { _, _, _ in })
    let token = try! XCTUnwrap(input.registry.registration(for: "test-device")).token

    input.receive(device: token, frame: 10, contacts: [])
    input.receive(device: token, frame: 10, contacts: [])
    input.receive(device: token, frame: 11, contacts: [])

    let snapshot = input.diagnosticsSnapshot()
    XCTAssertEqual(snapshot.acceptedDeliveries, 2)
    XCTAssertEqual(snapshot.sequenceStaleDrops, 1)
  }

  func testControllerCountsMainQueueSchedulingAndProcessing() {
    let input = MultitouchInputController(
      startBridge: { nil },
      stopBridge: {},
      enumerateDevices: {
        InputDeviceSnapshot(devices: [InputDeviceDescriptor(identity: "test-device", handle: 1)])
      })
    XCTAssertNil(input.start { _, _, _ in input.recordMainQueueScheduled() })
    input.receive(device: 1, frame: 1, contacts: [])
    input.recordMainQueueProcessed()

    let snapshot = input.diagnosticsSnapshot()
    XCTAssertEqual(snapshot.mainQueueScheduled, 1)
    XCTAssertEqual(snapshot.mainQueueProcessed, 1)
  }
}
