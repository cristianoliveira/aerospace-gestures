import XCTest

@testable import MultitouchInput

final class InputDiagnosticsTests: XCTestCase {
  func testSummaryUsesOnlyAggregateCountersAndKeepsIdleUnclassified() {
    let snapshot = InputDiagnosticsSnapshot(
      bridgeCallbackArrivals: 0,
      bridgeInvalidFrameRejects: 0,
      deviceRegistrationCalls: 0,
      deviceStopCalls: 0,
      registeredDevices: 0,
      lastCallbackAgeSeconds: nil,
      sequenceStaleDrops: 0,
      acceptedDeliveries: 0,
      mainQueueScheduled: 0,
      mainQueueProcessed: 0)

    XCTAssertEqual(
      snapshot.summary,
      "input-diagnostics callbacks=0 invalid_frames=0 register_calls=0 stop_calls=0 registered_devices=0 last_callback_age_s=none sequence_stale_drops=0 accepted_deliveries=0 main_queue_scheduled=0 main_queue_processed=0 input_state=unclassified"
    )
  }

  func testSummaryFormatsOnlyAggregateCountsAndCallbackAge() {
    let snapshot = InputDiagnosticsSnapshot(
      bridgeCallbackArrivals: 12,
      bridgeInvalidFrameRejects: 2,
      deviceRegistrationCalls: 3,
      deviceStopCalls: 1,
      registeredDevices: 2,
      lastCallbackAgeSeconds: 3456,
      sequenceStaleDrops: 4,
      acceptedDeliveries: 6,
      mainQueueScheduled: 6,
      mainQueueProcessed: 5)

    XCTAssertEqual(
      snapshot.summary,
      "input-diagnostics callbacks=12 invalid_frames=2 register_calls=3 stop_calls=1 registered_devices=2 last_callback_age_s=3456 sequence_stale_drops=4 accepted_deliveries=6 main_queue_scheduled=6 main_queue_processed=5 input_state=unclassified"
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
    let input = MultitouchInputController(startBridge: { nil }, stopBridge: {})
    XCTAssertNil(input.start { _, _, _ in })

    input.receive(device: 7, frame: 10, contacts: [])
    input.receive(device: 7, frame: 10, contacts: [])
    input.receive(device: 7, frame: 11, contacts: [])

    let snapshot = input.diagnosticsSnapshot()
    XCTAssertEqual(snapshot.acceptedDeliveries, 2)
    XCTAssertEqual(snapshot.sequenceStaleDrops, 1)
  }

  func testControllerCountsMainQueueSchedulingAndProcessing() {
    let input = MultitouchInputController(startBridge: { nil }, stopBridge: {})
    XCTAssertNil(input.start { _, _, _ in input.recordMainQueueScheduled() })
    input.receive(device: 1, frame: 1, contacts: [])
    input.recordMainQueueProcessed()

    let snapshot = input.diagnosticsSnapshot()
    XCTAssertEqual(snapshot.mainQueueScheduled, 1)
    XCTAssertEqual(snapshot.mainQueueProcessed, 1)
  }
}
