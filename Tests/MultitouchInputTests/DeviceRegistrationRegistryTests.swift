import XCTest

@testable import MultitouchInput

final class DeviceRegistrationRegistryTests: XCTestCase {
  func testZeroDeviceSnapshotCanLaterRegisterAnEnumeratedDevice() throws {
    var registry = DeviceRegistrationRegistry()

    let initial = try registry.reconcile([])
    XCTAssertTrue(initial.added.isEmpty)
    XCTAssertTrue(initial.removed.isEmpty)

    let reconnected = try registry.reconcile([device("external", handle: 7)])
    XCTAssertEqual(reconnected.added.map(\.descriptor.identity), ["external"])
    XCTAssertTrue(reconnected.removed.isEmpty)
    XCTAssertEqual(reconnected.added.first?.token, 1)
  }

  func testSameSnapshotIsIdempotentAndDoesNotDuplicateRegistrations() throws {
    var registry = DeviceRegistrationRegistry()
    let snapshot = [device("built-in", handle: 1), device("external", handle: 2)]

    let initial = try registry.reconcile(snapshot)
    let repeated = try registry.reconcile(snapshot)

    XCTAssertEqual(initial.added.count, 2)
    XCTAssertTrue(repeated.added.isEmpty)
    XCTAssertTrue(repeated.removed.isEmpty)
    XCTAssertEqual(registry.registrations.count, 2)
    XCTAssertEqual(registry.registrations.map(\.token), initial.added.map(\.token))
  }

  func testChangedSnapshotOnlyReplacesChangedDevice() throws {
    var registry = DeviceRegistrationRegistry()
    let initial = try registry.reconcile([
      device("built-in", handle: 1), device("old-external", handle: 2),
    ])
    let builtIn = try XCTUnwrap(initial.added.first { $0.descriptor.identity == "built-in" })

    let changed = try registry.reconcile([
      device("built-in", handle: 1), device("new-external", handle: 3),
    ])

    XCTAssertEqual(changed.removed.map(\.descriptor.identity), ["old-external"])
    XCTAssertEqual(changed.added.map(\.descriptor.identity), ["new-external"])
    XCTAssertEqual(registry.registration(for: "built-in"), builtIn)
  }

  func testHandleRewrappingForSameIdentityKeepsExistingRegistration() throws {
    var registry = DeviceRegistrationRegistry()
    let initial = try registry.reconcile([device("external", handle: 7)])
    let existing = try XCTUnwrap(initial.added.first)

    let refreshed = try registry.reconcile([device("external", handle: 8)])

    XCTAssertTrue(refreshed.added.isEmpty)
    XCTAssertTrue(refreshed.removed.isEmpty)
    XCTAssertEqual(registry.registration(for: "external"), existing)
    XCTAssertEqual(registry.registration(for: "external")?.descriptor.handle, 7)
  }

  func testRemovedThenReaddedRecycledHandleGetsAFreshToken() throws {
    var registry = DeviceRegistrationRegistry()
    let initial = try registry.reconcile([device("external", handle: 7)])
    let first = try XCTUnwrap(initial.added.first)

    XCTAssertEqual(try registry.reconcile([]).removed, [first])
    let reconnected = try registry.reconcile([device("external", handle: 7)])
    let second = try XCTUnwrap(reconnected.added.first)

    XCTAssertNotEqual(second.token, first.token)
    XCTAssertEqual(second.descriptor.handle, first.descriptor.handle)
  }

  func testForcedRebindReplacesEveryRegistrationEvenWhenIdentitiesAreUnchanged() throws {
    var registry = DeviceRegistrationRegistry()
    let initial = try registry.reconcile([
      device("built-in", handle: 1), device("external", handle: 2),
    ])
    let original = initial.added

    let rebound = try registry.reconcile(
      [
        device("built-in", handle: 3), device("external", handle: 4),
      ], forceRebind: true)

    XCTAssertEqual(rebound.removed, original)
    XCTAssertEqual(rebound.added.map(\.descriptor.identity), ["built-in", "external"])
    XCTAssertEqual(rebound.added.map(\.descriptor.handle), [3, 4])
    XCTAssertTrue(Set(rebound.added.map(\.token)).isDisjoint(with: Set(original.map(\.token))))
    XCTAssertEqual(registry.registrations, rebound.added)
  }

  func testDuplicateIdentityFailsClosedWithoutChangingActiveRegistrations() throws {
    var registry = DeviceRegistrationRegistry()
    let initial = try registry.reconcile([device("built-in", handle: 1)])
    let builtIn = try XCTUnwrap(initial.added.first)

    XCTAssertThrowsError(
      try registry.reconcile([
        device("built-in", handle: 1), device("built-in", handle: 2),
      ]))

    XCTAssertEqual(registry.registrations, [builtIn])
  }

  func testStopClearsRegistrationsAndIsIdempotent() throws {
    var registry = DeviceRegistrationRegistry()
    let initial = try registry.reconcile([device("built-in", handle: 1)])
    let registration = try XCTUnwrap(initial.added.first)

    XCTAssertEqual(registry.removeAll(), [registration])
    XCTAssertTrue(registry.removeAll().isEmpty)
    XCTAssertTrue(registry.registrations.isEmpty)
  }

  private func device(_ identity: String, handle: UInt) -> InputDeviceDescriptor {
    InputDeviceDescriptor(identity: identity, handle: handle)
  }
}
