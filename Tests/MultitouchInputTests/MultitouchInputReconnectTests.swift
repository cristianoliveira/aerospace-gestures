import Dispatch
import GestureCore
import XCTest

@testable import MultitouchInput

final class MultitouchInputReconnectTests: XCTestCase {
  func testListenerStartsWithNoDevicesAndRegistersOneThatAppearsLater() {
    let external = device("external", handle: 2)
    var snapshots: [InputDeviceSnapshot?] = [
      InputDeviceSnapshot(devices: []),
      InputDeviceSnapshot(devices: [external]),
    ]
    var registrations: [DeviceRegistration] = []
    let input = MultitouchInputController(
      startBridge: { nil },
      stopBridge: {},
      enumerateDevices: { snapshots.removeFirst() },
      registerDevice: { handle, token in
        registrations.append(DeviceRegistration(descriptor: external, token: token))
        return handle == external.handle
      })

    XCTAssertNil(input.start(onFrame: { _, _, _ in }))
    XCTAssertTrue(input.registry.registrations.isEmpty)
    input.handleDeviceTopologyChange()

    XCTAssertEqual(registrations.count, 1)
    XCTAssertEqual(input.registry.registrations, registrations)
    input.stop()
  }

  func testUnstableIdentityUsesOneShotRegistrationWithoutRefreshingPointers() {
    let firstHandle = device("handle:1", handle: 1)
    let rewrappedHandle = device("handle:2", handle: 2)
    var snapshots: [InputDeviceSnapshot?] = [
      InputDeviceSnapshot(devices: [firstHandle], supportsStableIdentity: false),
      InputDeviceSnapshot(devices: [rewrappedHandle], supportsStableIdentity: false),
    ]
    var registrations: [DeviceRegistration] = []
    let input = MultitouchInputController(
      startBridge: { nil },
      stopBridge: {},
      enumerateDevices: { snapshots.removeFirst() },
      registerDevice: { handle, token in
        registrations.append(DeviceRegistration(descriptor: firstHandle, token: token))
        return handle == firstHandle.handle
      })

    XCTAssertNil(input.start(onFrame: { _, _, _ in }))
    input.refreshDevices()

    XCTAssertEqual(registrations.count, 1)
    XCTAssertEqual(snapshots.count, 1)
    XCTAssertEqual(input.registry.registrations.first?.descriptor.handle, 1)
    XCTAssertFalse(input.diagnosticsSnapshot().identityGettersAvailable)
    input.stop()
  }

  func testIdleRefreshDoesNotRewrapRegisteredHandlesOrEnumerateAgain() {
    let firstHandle = device("stable-id", handle: 1)
    let rewrappedHandle = device("stable-id", handle: 2)
    var releasedSnapshots: [String] = []
    var snapshots: [InputDeviceSnapshot?] = [
      InputDeviceSnapshot(
        devices: [firstHandle],
        lifetime: SnapshotLifetimeProbe { releasedSnapshots.append("first") }),
      InputDeviceSnapshot(
        devices: [rewrappedHandle],
        lifetime: SnapshotLifetimeProbe { releasedSnapshots.append("second") }),
    ]
    var registeredHandles: [UInt] = []
    let input = MultitouchInputController(
      startBridge: { nil },
      stopBridge: {},
      enumerateDevices: { snapshots.removeFirst() },
      registerDevice: { handle, _ in
        registeredHandles.append(handle)
        return true
      },
      unregisterDevice: { _, _ in })

    XCTAssertNil(input.start(onFrame: { _, _, _ in }))
    input.refreshDevices()

    XCTAssertEqual(registeredHandles, [1])
    XCTAssertEqual(releasedSnapshots, [])
    XCTAssertEqual(snapshots.count, 1)
    XCTAssertEqual(input.registry.registrations.first?.descriptor.handle, 1)
    input.stop()
    XCTAssertEqual(releasedSnapshots, ["first"])
  }

  func testFailedTopologySnapshotKeepsOldRegistrationUntilForcedRetryRebindsCurrentSnapshot() {
    let builtIn = device("built-in", handle: 1)
    let external = device("external", handle: 2)
    var snapshots: [InputDeviceSnapshot?] = [
      InputDeviceSnapshot(devices: [builtIn]),
      nil,
      InputDeviceSnapshot(devices: [builtIn, external]),
    ]
    var registrations: [DeviceRegistration] = []
    var unregistrations: [DeviceRegistration] = []
    let input = MultitouchInputController(
      startBridge: { nil },
      stopBridge: {},
      enumerateDevices: { snapshots.removeFirst() },
      registerDevice: { handle, token in
        registrations.append(
          DeviceRegistration(descriptor: handle == 1 ? builtIn : external, token: token))
        return true
      },
      unregisterDevice: { handle, token in
        unregistrations.append(
          DeviceRegistration(descriptor: handle == 1 ? builtIn : external, token: token))
      })

    XCTAssertNil(input.start(onFrame: { _, _, _ in }))
    let initial = try! XCTUnwrap(input.registry.registration(for: "built-in"))
    input.handleDeviceTopologyChange()

    XCTAssertEqual(input.registry.registration(for: "built-in"), initial)
    XCTAssertTrue(unregistrations.isEmpty)
    XCTAssertEqual(input.diagnosticsSnapshot().deviceEnumerationFailures, 1)

    input.refreshDevices()

    XCTAssertEqual(
      registrations.map(\.descriptor.identity), ["built-in", "built-in", "external"])
    XCTAssertEqual(unregistrations.map(\.token), [initial.token])
    XCTAssertNotEqual(input.registry.registration(for: "built-in")?.token, initial.token)
    XCTAssertNotNil(input.registry.registration(for: "external"))
    XCTAssertEqual(input.diagnosticsSnapshot().deviceTopologyRebinds, 1)
    input.stop()
  }

  func testRepeatedSnapshotsRegisterOnceAndRemovedThenReaddedDeviceGetsFreshToken() {
    let external = device("external", handle: 7)
    var snapshots: [InputDeviceSnapshot?] = [
      InputDeviceSnapshot(devices: [external]),
      InputDeviceSnapshot(devices: []),
      InputDeviceSnapshot(devices: [external]),
    ]
    var registrations: [DeviceRegistration] = []
    var removals: [UInt] = []
    var delivered: [(UInt, UInt32)] = []
    let input = MultitouchInputController(
      startBridge: { nil },
      stopBridge: {},
      enumerateDevices: { snapshots.removeFirst() },
      registerDevice: { handle, token in
        registrations.append(
          DeviceRegistration(descriptor: external.replacingHandle(handle), token: token))
        return true
      },
      unregisterDevice: { _, _ in })

    XCTAssertNil(
      input.start(
        onFrame: { device, frame, _ in delivered.append((device, frame)) },
        onDeviceRemoved: { removals.append($0) }))
    let first = try! XCTUnwrap(input.registry.registration(for: "external"))
    input.refreshDevices()
    XCTAssertEqual(registrations.count, 1)
    XCTAssertEqual(input.registry.registration(for: "external"), first)

    input.receive(device: first.token, frame: 100, contacts: [])
    input.handleDeviceTopologyChange()
    XCTAssertFalse(input.isDeviceRegistered(first.token))
    input.handleDeviceTopologyChange()
    let second = try! XCTUnwrap(input.registry.registration(for: "external"))
    input.receive(device: second.token, frame: 0, contacts: [])

    input.receive(device: first.token, frame: 101, contacts: [])

    XCTAssertNotEqual(first.token, second.token)
    XCTAssertFalse(input.isDeviceRegistered(first.token))
    XCTAssertEqual(removals, [first.token])
    XCTAssertEqual(delivered.map(\.0), [first.token, second.token])
    XCTAssertEqual(registrations.map(\.token), [first.token, second.token])
    input.stop()
  }

  func testRegistrationFailureRetriesOnNextSnapshotWithoutDuplicateCallback() {
    let external = device("external", handle: 7)
    var snapshots: [InputDeviceSnapshot?] = [
      InputDeviceSnapshot(devices: [external]),
      InputDeviceSnapshot(devices: [external]),
    ]
    var registrationAttempts: [UInt] = []
    var acceptsNextRegistration = false
    let input = MultitouchInputController(
      startBridge: { nil },
      stopBridge: {},
      enumerateDevices: { snapshots.removeFirst() },
      registerDevice: { _, token in
        registrationAttempts.append(token)
        return acceptsNextRegistration
      },
      unregisterDevice: { _, _ in })

    XCTAssertNil(input.start(onFrame: { _, _, _ in }))
    XCTAssertTrue(input.registry.registrations.isEmpty)
    XCTAssertEqual(input.diagnosticsSnapshot().deviceRegistrationFailures, 1)

    acceptsNextRegistration = true
    input.refreshDevices()

    XCTAssertEqual(registrationAttempts.count, 2)
    XCTAssertNotEqual(registrationAttempts[0], registrationAttempts[1])
    XCTAssertEqual(input.registry.registrations.map(\.token), [registrationAttempts[1]])
    input.stop()
  }

  func testTopologyEventRebindsAllDevicesAndRejectsOldGenerationCallbacks() {
    let builtIn = device("built-in", handle: 1)
    let external = device("external", handle: 2)
    var snapshots: [InputDeviceSnapshot?] = [
      InputDeviceSnapshot(devices: [builtIn, external]),
      InputDeviceSnapshot(devices: [builtIn, external]),
    ]
    var registeredHandles: [UInt] = []
    var unregisteredTokens: [UInt] = []
    var removedTokens: [UInt] = []
    var deliveredTokens: [UInt] = []
    let input = MultitouchInputController(
      startBridge: { nil },
      stopBridge: {},
      enumerateDevices: { snapshots.removeFirst() },
      registerDevice: { handle, _ in
        registeredHandles.append(handle)
        return true
      },
      unregisterDevice: { _, token in unregisteredTokens.append(token) })

    XCTAssertNil(
      input.start(
        onFrame: { token, _, _ in deliveredTokens.append(token) },
        onDeviceRemoved: { removedTokens.append($0) }))
    let oldRegistrations = input.registry.registrations

    input.handleDeviceTopologyChange()

    let newRegistrations = input.registry.registrations
    for old in oldRegistrations {
      input.receive(device: old.token, frame: 1, contacts: [])
    }
    for new in newRegistrations {
      input.receive(device: new.token, frame: 1, contacts: [])
    }

    XCTAssertEqual(registeredHandles, [1, 2, 1, 2])
    XCTAssertEqual(unregisteredTokens, oldRegistrations.map(\.token))
    XCTAssertEqual(removedTokens, oldRegistrations.map(\.token))
    XCTAssertTrue(
      Set(oldRegistrations.map(\.token)).isDisjoint(with: Set(newRegistrations.map(\.token))))
    XCTAssertEqual(deliveredTokens, newRegistrations.map(\.token))
    XCTAssertEqual(input.diagnosticsSnapshot().deviceTopologyRebinds, 1)
    XCTAssertEqual(input.diagnosticsSnapshot().topologyEventRebindAttempts, 1)
    input.stop()
  }

  func testDeferredTopologyRefreshRebindsWhenSnapshotCountGrows() {
    let builtIn = device("built-in", handle: 1)
    let external = device("external", handle: 2)
    var snapshots: [InputDeviceSnapshot?] = [
      InputDeviceSnapshot(devices: [builtIn]),
      InputDeviceSnapshot(devices: [builtIn]),
      InputDeviceSnapshot(devices: [builtIn, external]),
    ]
    var workItems: [DispatchWorkItem] = []
    var delays: [TimeInterval] = []
    var registered: [UInt] = []
    var unregistered: [UInt] = []
    var delivered: [UInt] = []
    let input = MultitouchInputController(
      startBridge: { nil },
      stopBridge: {},
      enumerateDevices: { snapshots.removeFirst() },
      registerDevice: { handle, _ in
        registered.append(handle)
        return true
      },
      unregisterDevice: { handle, _ in unregistered.append(handle) },
      scheduleDeferredTopologyRefresh: { workItem, delay in
        workItems.append(workItem)
        delays.append(delay)
      })

    XCTAssertNil(input.start(onFrame: { device, _, _ in delivered.append(device) }))
    input.handleDeviceTopologyChange()

    XCTAssertEqual(workItems.count, 1)
    XCTAssertEqual(delays, [2])
    XCTAssertEqual(input.registry.registrations.count, 1)

    workItems[0].perform()

    XCTAssertEqual(registered, [1, 1, 1, 2])
    XCTAssertEqual(unregistered.count, 2)
    XCTAssertEqual(
      input.registry.registrations.map(\.descriptor.identity), ["built-in", "external"])
    let externalToken = try! XCTUnwrap(input.registry.registration(for: "external")).token
    input.receive(device: externalToken, frame: 1, contacts: [])
    XCTAssertEqual(delivered, [externalToken])
    XCTAssertEqual(input.diagnosticsSnapshot().deferredTopologyRebindAttempts, 1)
    XCTAssertEqual(input.diagnosticsSnapshot().topologyRetryRebindAttempts, 0)
    input.stop()
  }

  func testDeferredTopologyRefreshDoesNotRebindWhenSnapshotCountIsUnchanged() {
    let builtIn = device("built-in", handle: 1)
    var snapshots: [InputDeviceSnapshot?] = [
      InputDeviceSnapshot(devices: [builtIn]),
      InputDeviceSnapshot(devices: [builtIn]),
      InputDeviceSnapshot(devices: [builtIn]),
    ]
    var workItems: [DispatchWorkItem] = []
    var enumerationCount = 0
    var registered: [UInt] = []
    var unregistered: [UInt] = []
    let input = MultitouchInputController(
      startBridge: { nil },
      stopBridge: {},
      enumerateDevices: {
        enumerationCount += 1
        return snapshots.removeFirst()
      },
      registerDevice: { handle, _ in
        registered.append(handle)
        return true
      },
      unregisterDevice: { handle, _ in unregistered.append(handle) },
      scheduleDeferredTopologyRefresh: { workItem, _ in workItems.append(workItem) })

    XCTAssertNil(input.start(onFrame: { _, _, _ in }))
    input.handleDeviceTopologyChange()
    let registrationsAfterEvent = registered
    let unregistrationsAfterEvent = unregistered

    workItems[0].perform()

    XCTAssertEqual(registered, registrationsAfterEvent)
    XCTAssertEqual(unregistered, unregistrationsAfterEvent)
    XCTAssertEqual(input.diagnosticsSnapshot().deferredTopologyRebindAttempts, 0)
    XCTAssertEqual(enumerationCount, 3)
    input.stop()
  }

  func testDeferredCheckIsScheduledAfterFailedEventRecoverySucceeds() {
    let builtIn = device("built-in", handle: 1)
    var snapshots: [InputDeviceSnapshot?] = [
      InputDeviceSnapshot(devices: [builtIn]),
      nil,
      InputDeviceSnapshot(devices: [builtIn]),
    ]
    var workItems: [DispatchWorkItem] = []
    var delays: [TimeInterval] = []
    let input = MultitouchInputController(
      startBridge: { nil },
      stopBridge: {},
      enumerateDevices: { snapshots.removeFirst() },
      scheduleDeferredTopologyRefresh: { workItem, delay in
        workItems.append(workItem)
        delays.append(delay)
      })

    XCTAssertNil(input.start(onFrame: { _, _, _ in }))
    input.handleDeviceTopologyChange()
    XCTAssertTrue(input.diagnosticsSnapshot().topologyRebindPending)
    XCTAssertTrue(workItems.isEmpty)

    input.refreshDevices()

    XCTAssertFalse(input.diagnosticsSnapshot().topologyRebindPending)
    XCTAssertEqual(workItems.count, 1)
    XCTAssertEqual(delays, [2])
    input.stop()
  }

  func testDeferredCountCheckUsesSnapshotCountWhenRegistrationFailed() {
    let builtIn = device("built-in", handle: 1)
    let external = device("external", handle: 2)
    var snapshots: [InputDeviceSnapshot?] = [
      InputDeviceSnapshot(devices: [builtIn, external]),
      InputDeviceSnapshot(devices: [builtIn, external]),
      InputDeviceSnapshot(devices: [builtIn, external]),
    ]
    var workItems: [DispatchWorkItem] = []
    var registered: [UInt] = []
    let input = MultitouchInputController(
      startBridge: { nil },
      stopBridge: {},
      enumerateDevices: { snapshots.removeFirst() },
      registerDevice: { handle, _ in
        registered.append(handle)
        return handle == builtIn.handle
      },
      scheduleDeferredTopologyRefresh: { workItem, _ in workItems.append(workItem) })

    XCTAssertNil(input.start(onFrame: { _, _, _ in }))
    XCTAssertEqual(input.registry.registrations.count, 1)
    input.handleDeviceTopologyChange()
    let registrationsAfterEvent = registered

    workItems[0].perform()

    XCTAssertEqual(registered, registrationsAfterEvent)
    XCTAssertEqual(input.registry.registrations.count, 1)
    XCTAssertEqual(input.diagnosticsSnapshot().deviceRegistrationFailures, 2)
    XCTAssertEqual(input.diagnosticsSnapshot().deferredTopologyRebindAttempts, 0)
    input.stop()
  }

  func testDeferredTopologyRefreshFailureDoesNotRebindOrScheduleAnotherRetry() {
    let builtIn = device("built-in", handle: 1)
    var snapshots: [InputDeviceSnapshot?] = [
      InputDeviceSnapshot(devices: [builtIn]),
      InputDeviceSnapshot(devices: [builtIn]),
      nil,
    ]
    var workItems: [DispatchWorkItem] = []
    var registered: [UInt] = []
    var unregistered: [UInt] = []
    let input = MultitouchInputController(
      startBridge: { nil },
      stopBridge: {},
      enumerateDevices: { snapshots.removeFirst() },
      registerDevice: { handle, _ in
        registered.append(handle)
        return true
      },
      unregisterDevice: { handle, _ in unregistered.append(handle) },
      scheduleDeferredTopologyRefresh: { workItem, _ in workItems.append(workItem) })

    XCTAssertNil(input.start(onFrame: { _, _, _ in }))
    input.handleDeviceTopologyChange()
    workItems[0].perform()

    XCTAssertEqual(registered, [1, 1])
    XCTAssertEqual(unregistered.count, 1)
    XCTAssertEqual(input.diagnosticsSnapshot().deviceEnumerationFailures, 1)
    XCTAssertEqual(input.diagnosticsSnapshot().deferredTopologyRebindAttempts, 0)
    XCTAssertEqual(workItems.count, 1)
    input.stop()
  }

  func testDeferredTopologyRefreshCoalescesTopologyEvents() {
    let builtIn = device("built-in", handle: 1)
    var snapshots: [InputDeviceSnapshot?] = [
      InputDeviceSnapshot(devices: [builtIn]),
      InputDeviceSnapshot(devices: [builtIn]),
      InputDeviceSnapshot(devices: [builtIn]),
      InputDeviceSnapshot(devices: [builtIn]),
    ]
    var workItems: [DispatchWorkItem] = []
    var enumerationCount = 0
    let input = MultitouchInputController(
      startBridge: { nil },
      stopBridge: {},
      enumerateDevices: {
        enumerationCount += 1
        return snapshots.removeFirst()
      },
      scheduleDeferredTopologyRefresh: { workItem, _ in workItems.append(workItem) })

    XCTAssertNil(input.start(onFrame: { _, _, _ in }))
    input.handleDeviceTopologyChange()
    input.handleDeviceTopologyChange()

    XCTAssertEqual(workItems.count, 2)
    XCTAssertTrue(workItems[0].isCancelled)
    workItems[1].perform()

    XCTAssertEqual(input.diagnosticsSnapshot().topologyEventRebindAttempts, 2)
    XCTAssertEqual(input.diagnosticsSnapshot().deferredTopologyRebindAttempts, 0)
    XCTAssertEqual(enumerationCount, 4)
    input.stop()
  }

  func testStopCancelsDeferredTopologyRefresh() {
    let builtIn = device("built-in", handle: 1)
    var snapshots: [InputDeviceSnapshot?] = [
      InputDeviceSnapshot(devices: [builtIn]),
      InputDeviceSnapshot(devices: [builtIn]),
      InputDeviceSnapshot(devices: [device("external", handle: 2)]),
    ]
    var workItems: [DispatchWorkItem] = []
    var enumerationCount = 0
    var registered: [UInt] = []
    let input = MultitouchInputController(
      startBridge: { nil },
      stopBridge: {},
      enumerateDevices: {
        enumerationCount += 1
        return snapshots.removeFirst()
      },
      registerDevice: { handle, _ in
        registered.append(handle)
        return true
      },
      scheduleDeferredTopologyRefresh: { workItem, _ in workItems.append(workItem) })

    XCTAssertNil(input.start(onFrame: { _, _, _ in }))
    input.handleDeviceTopologyChange()
    input.stop()
    XCTAssertNil(input.start(onFrame: { _, _, _ in }))
    workItems[0].perform()

    XCTAssertTrue(workItems[0].isCancelled)
    XCTAssertEqual(enumerationCount, 3)
    XCTAssertEqual(registered, [1, 1, 2])
    XCTAssertEqual(input.registry.registrations.map(\.descriptor.identity), ["external"])
    input.stop()
  }

  func testFailedTopologySnapshotRetriesAsForcedRebindOnNextPoll() {
    let oldDevice = device("external", handle: 1)
    let reconnectedDevice = device("external", handle: 2)
    var snapshots: [InputDeviceSnapshot?] = [
      InputDeviceSnapshot(devices: [oldDevice]),
      nil,
      InputDeviceSnapshot(devices: [reconnectedDevice]),
    ]
    var registered: [DeviceRegistration] = []
    var unregistered: [DeviceRegistration] = []
    let input = MultitouchInputController(
      startBridge: { nil },
      stopBridge: {},
      enumerateDevices: { snapshots.removeFirst() },
      registerDevice: { handle, token in
        registered.append(
          DeviceRegistration(descriptor: reconnectedDevice.replacingHandle(handle), token: token))
        return true
      },
      unregisterDevice: { handle, token in
        unregistered.append(
          DeviceRegistration(descriptor: oldDevice.replacingHandle(handle), token: token))
      })

    XCTAssertNil(input.start(onFrame: { _, _, _ in }))
    let original = try! XCTUnwrap(input.registry.registration(for: "external"))
    input.handleDeviceTopologyChange()

    XCTAssertTrue(input.isDeviceRegistered(original.token))
    XCTAssertTrue(input.diagnosticsSnapshot().topologyRebindPending)
    input.refreshDevices()

    let rebound = try! XCTUnwrap(input.registry.registration(for: "external"))
    XCTAssertNotEqual(rebound.token, original.token)
    XCTAssertEqual(rebound.descriptor.handle, 2)
    XCTAssertFalse(input.isDeviceRegistered(original.token))
    XCTAssertEqual(unregistered.map(\.token), [original.token])
    XCTAssertEqual(registered.map(\.token), [original.token, rebound.token])
    XCTAssertFalse(input.diagnosticsSnapshot().topologyRebindPending)
    XCTAssertEqual(input.diagnosticsSnapshot().deviceTopologyRebinds, 1)
    XCTAssertEqual(input.diagnosticsSnapshot().topologyEventRebindAttempts, 1)
    XCTAssertEqual(input.diagnosticsSnapshot().topologyRetryRebindAttempts, 1)
    input.stop()
  }

  func testUnstableIdentityRegistrationFailureRemainsPendingUntilAForcedRetry() {
    let external = device("handle:1", handle: 1)
    var snapshots: [InputDeviceSnapshot?] = [
      InputDeviceSnapshot(devices: [external], supportsStableIdentity: false),
      InputDeviceSnapshot(devices: [external], supportsStableIdentity: false),
      InputDeviceSnapshot(devices: [external], supportsStableIdentity: false),
    ]
    var outcomes = [true, false, true]
    var registrationTokens: [UInt] = []
    let input = MultitouchInputController(
      startBridge: { nil },
      stopBridge: {},
      enumerateDevices: { snapshots.removeFirst() },
      registerDevice: { _, token in
        registrationTokens.append(token)
        return outcomes.removeFirst()
      })

    XCTAssertNil(input.start(onFrame: { _, _, _ in }))
    let original = try! XCTUnwrap(input.registry.registration(for: "handle:1"))
    input.handleDeviceTopologyChange()

    XCTAssertTrue(input.diagnosticsSnapshot().topologyRebindPending)
    XCTAssertEqual(input.diagnosticsSnapshot().deviceTopologyRebinds, 1)
    input.refreshDevices()

    let rebound = try! XCTUnwrap(input.registry.registration(for: "handle:1"))
    XCTAssertNotEqual(rebound.token, original.token)
    XCTAssertFalse(input.diagnosticsSnapshot().topologyRebindPending)
    XCTAssertEqual(input.diagnosticsSnapshot().deviceTopologyRebinds, 1)
    XCTAssertEqual(registrationTokens, [1, 2, 3])
    input.stop()
  }

  func testInitialUnstableRegistrationFailureRetriesTheSameHandle() {
    let external = device("handle:1", handle: 1)
    var outcomes = [false, true]
    var registrationTokens: [UInt] = []
    let input = MultitouchInputController(
      startBridge: { nil },
      stopBridge: {},
      enumerateDevices: {
        InputDeviceSnapshot(devices: [external], supportsStableIdentity: false)
      },
      registerDevice: { _, token in
        registrationTokens.append(token)
        return outcomes.removeFirst()
      })

    XCTAssertNil(input.start(onFrame: { _, _, _ in }))
    XCTAssertTrue(input.diagnosticsSnapshot().topologyRebindPending)
    input.refreshDevices()

    XCTAssertEqual(registrationTokens, [1, 2])
    XCTAssertTrue(input.isDeviceRegistered(2))
    XCTAssertFalse(input.diagnosticsSnapshot().topologyRebindPending)
    input.stop()
  }

  func testPersistentRegistrationFailureDoesNotRebindHealthyDevicesOnEveryPoll() {
    let builtIn = device("built-in", handle: 1)
    let external = device("external", handle: 2)
    var snapshots: [InputDeviceSnapshot?] = [
      InputDeviceSnapshot(devices: [builtIn, external]),
      InputDeviceSnapshot(devices: [builtIn, external]),
      InputDeviceSnapshot(devices: [builtIn, external]),
      InputDeviceSnapshot(devices: [builtIn, external]),
      InputDeviceSnapshot(devices: [builtIn, external]),
    ]
    var outcomes = [true, true, true, false, false, false]
    var registeredHandles: [UInt] = []
    var unregisteredTokens: [UInt] = []
    let input = MultitouchInputController(
      startBridge: { nil },
      stopBridge: {},
      enumerateDevices: { snapshots.removeFirst() },
      registerDevice: { handle, _ in
        registeredHandles.append(handle)
        return outcomes.removeFirst()
      },
      unregisterDevice: { _, token in unregisteredTokens.append(token) })

    XCTAssertNil(input.start(onFrame: { _, _, _ in }))
    input.handleDeviceTopologyChange()
    let healthy = try! XCTUnwrap(input.registry.registration(for: "built-in"))
    input.refreshDevices()
    XCTAssertTrue(input.diagnosticsSnapshot().topologyRebindPending)
    input.refreshDevices()
    XCTAssertFalse(input.diagnosticsSnapshot().topologyRebindPending)
    input.refreshDevices()

    XCTAssertEqual(registeredHandles, [1, 2, 1, 2, 2, 2])
    XCTAssertEqual(unregisteredTokens, [1, 2])
    XCTAssertEqual(input.registry.registration(for: "built-in"), healthy)
    XCTAssertEqual(input.diagnosticsSnapshot().deviceRegistrationFailures, 3)
    input.stop()
  }

  func testIdleTicksAvoidIdentityPollingThenTopologyEventRebindsCurrentHandles() {
    let initialDevices = [device("initial-a", handle: 1), device("initial-b", handle: 2)]
    let replacementDevices = [
      device("replacement-a", handle: 3), device("replacement-b", handle: 4),
    ]
    var snapshots: [InputDeviceSnapshot?] = [
      InputDeviceSnapshot(devices: initialDevices),
      InputDeviceSnapshot(devices: replacementDevices),
    ]
    var enumerationCount = 0
    var registeredHandles: [UInt] = []
    var unregisteredTokens: [UInt] = []
    var deliveredTokens: [UInt] = []
    let input = MultitouchInputController(
      startTopologyObserver: { true },
      startBridge: { nil },
      stopBridge: {},
      enumerateDevices: {
        enumerationCount += 1
        return snapshots.removeFirst()
      },
      registerDevice: { handle, _ in
        registeredHandles.append(handle)
        return true
      },
      unregisterDevice: { _, token in unregisteredTokens.append(token) })

    XCTAssertNil(input.start(onFrame: { token, _, _ in deliveredTokens.append(token) }))
    let initialRegistrations = input.registry.registrations
    for _ in 0..<3 {
      input.refreshDevices()
      input.checkDeviceCountIfObserverUnavailable()
    }

    XCTAssertEqual(enumerationCount, 1)
    XCTAssertEqual(registeredHandles, [1, 2])
    XCTAssertTrue(unregisteredTokens.isEmpty)
    XCTAssertEqual(input.diagnosticsSnapshot().deviceCountWatchdogRuns, 0)

    input.handleDeviceTopologyChange()
    let currentRegistrations = input.registry.registrations
    for old in initialRegistrations {
      input.receive(device: old.token, frame: 1, contacts: [])
    }
    for current in currentRegistrations {
      input.receive(device: current.token, frame: 1, contacts: [])
    }

    XCTAssertEqual(enumerationCount, 2)
    XCTAssertEqual(registeredHandles, [1, 2, 3, 4])
    XCTAssertEqual(unregisteredTokens, initialRegistrations.map(\.token))
    XCTAssertTrue(
      Set(initialRegistrations.map(\.token)).isDisjoint(
        with: Set(currentRegistrations.map(\.token))))
    XCTAssertEqual(deliveredTokens, currentRegistrations.map(\.token))
    XCTAssertEqual(input.diagnosticsSnapshot().topologyRebindBegins, 1)
    XCTAssertEqual(input.diagnosticsSnapshot().topologyRebindEnds, 1)
    XCTAssertEqual(input.diagnosticsSnapshot().deviceTopologyRebinds, 1)
    XCTAssertEqual(input.diagnosticsSnapshot().topologyEventRebindAttempts, 1)
    input.stop()
  }

  func testUnavailableObserverWatchdogOnlyRebindsOnDeviceCountChange() {
    let initial = device("initial", handle: 1)
    let sameCountReplacement = device("replacement", handle: 2)
    let addedDevice = device("added", handle: 4)
    var snapshots: [InputDeviceSnapshot?] = [
      InputDeviceSnapshot(devices: [initial]),
      InputDeviceSnapshot(devices: [sameCountReplacement]),
      InputDeviceSnapshot(devices: [sameCountReplacement, addedDevice]),
    ]
    var registrations: [UInt] = []
    var unregistrations: [UInt] = []
    let input = MultitouchInputController(
      startTopologyObserver: { false },
      startBridge: { nil },
      stopBridge: {},
      enumerateDevices: { snapshots.removeFirst() },
      registerDevice: { handle, _ in
        registrations.append(handle)
        return true
      },
      unregisterDevice: { handle, _ in unregistrations.append(handle) })

    XCTAssertNil(input.start(onFrame: { _, _, _ in }))
    input.checkDeviceCountIfObserverUnavailable()
    XCTAssertEqual(registrations, [1])
    XCTAssertTrue(unregistrations.isEmpty)
    XCTAssertEqual(input.diagnosticsSnapshot().deviceCountChanges, 0)

    input.checkDeviceCountIfObserverUnavailable()
    XCTAssertEqual(registrations, [1, 4, 2])
    XCTAssertEqual(unregistrations, [1])
    XCTAssertEqual(
      input.registry.registrations.map(\.descriptor.identity), ["added", "replacement"])
    XCTAssertEqual(input.diagnosticsSnapshot().deviceCountWatchdogRuns, 2)
    XCTAssertEqual(input.diagnosticsSnapshot().deviceCountChanges, 1)
    XCTAssertEqual(input.diagnosticsSnapshot().deviceTopologyRebinds, 1)
    XCTAssertEqual(input.diagnosticsSnapshot().countChangeRebindAttempts, 1)
    input.stop()
  }

  func testSyntheticTopologyFeedbackCountsForcedRebindCyclesWithoutIOKit() {
    let external = device("external", handle: 1)
    var input: MultitouchInputController!
    var queuedTopologyEvents: [() -> Void] = []
    input = MultitouchInputController(
      startTopologyObserver: { true },
      startBridge: { nil },
      stopBridge: {},
      enumerateDevices: { InputDeviceSnapshot(devices: [external]) },
      registerDevice: { _, _ in
        queuedTopologyEvents.append { input.handleDeviceTopologyChange() }
        return true
      },
      unregisterDevice: { _, _ in
        queuedTopologyEvents.append { input.handleDeviceTopologyChange() }
      })

    XCTAssertNil(input.start(onFrame: { _, _, _ in }))
    for _ in 0..<3 {
      queuedTopologyEvents.removeFirst()()
    }

    let diagnostics = input.diagnosticsSnapshot()
    XCTAssertEqual(diagnostics.topologyRebindBegins, 3)
    XCTAssertEqual(diagnostics.topologyRebindEnds, 3)
    XCTAssertEqual(diagnostics.deviceTopologyRebinds, 3)
    XCTAssertEqual(queuedTopologyEvents.count, 4)
    input.stop()
  }

  func testTopologyEventRebindsWhenStableIdentityGettersAreUnavailable() {
    let external = device("handle:1", handle: 1)
    var snapshots: [InputDeviceSnapshot?] = [
      InputDeviceSnapshot(devices: [external], supportsStableIdentity: false),
      InputDeviceSnapshot(devices: [external], supportsStableIdentity: false),
    ]
    var registrationTokens: [UInt] = []
    let input = MultitouchInputController(
      startBridge: { nil },
      stopBridge: {},
      enumerateDevices: { snapshots.removeFirst() },
      registerDevice: { _, token in
        registrationTokens.append(token)
        return true
      })

    XCTAssertNil(input.start(onFrame: { _, _, _ in }))
    input.handleDeviceTopologyChange()

    XCTAssertEqual(registrationTokens, [1, 2])
    XCTAssertFalse(input.diagnosticsSnapshot().identityGettersAvailable)
    XCTAssertEqual(input.diagnosticsSnapshot().deviceTopologyRebinds, 1)
    input.stop()
  }

  func testStopSerializesWithInFlightRefreshAndPreventsLaterRegistrations() {
    let external = device("external", handle: 7)
    let enteredEnumeration = DispatchSemaphore(value: 0)
    let continueEnumeration = DispatchSemaphore(value: 0)
    let stopStarted = DispatchSemaphore(value: 0)
    let refreshFinished = DispatchSemaphore(value: 0)
    let stopFinished = DispatchSemaphore(value: 0)
    let callsLock = NSLock()
    var enumerationCount = 0
    var registrations: [UInt] = []
    var unregistrations: [UInt] = []
    let input = MultitouchInputController(
      startBridge: { nil },
      stopBridge: {},
      enumerateDevices: {
        callsLock.lock()
        enumerationCount += 1
        let current = enumerationCount
        callsLock.unlock()
        if current == 1 { return InputDeviceSnapshot(devices: []) }
        enteredEnumeration.signal()
        continueEnumeration.wait()
        return InputDeviceSnapshot(devices: [external])
      },
      registerDevice: { _, token in
        registrations.append(token)
        return true
      },
      unregisterDevice: { _, token in
        unregistrations.append(token)
      })

    XCTAssertNil(input.start(onFrame: { _, _, _ in }))
    DispatchQueue.global().async {
      input.checkDeviceCountIfObserverUnavailable()
      refreshFinished.signal()
    }
    XCTAssertEqual(enteredEnumeration.wait(timeout: .now() + 2), .success)

    DispatchQueue.global().async {
      stopStarted.signal()
      input.stop()
      stopFinished.signal()
    }
    XCTAssertEqual(stopStarted.wait(timeout: .now() + 2), .success)
    continueEnumeration.signal()
    XCTAssertEqual(refreshFinished.wait(timeout: .now() + 2), .success)
    XCTAssertEqual(stopFinished.wait(timeout: .now() + 2), .success)

    input.refreshDevices()
    XCTAssertEqual(registrations.count, 1)
    XCTAssertEqual(unregistrations, registrations)
    XCTAssertTrue(input.registry.registrations.isEmpty)
  }

  private func device(_ identity: String, handle: UInt) -> InputDeviceDescriptor {
    InputDeviceDescriptor(identity: identity, handle: handle)
  }
}

extension InputDeviceDescriptor {
  fileprivate func replacingHandle(_ handle: UInt) -> Self {
    Self(identity: identity, handle: handle)
  }
}

private final class SnapshotLifetimeProbe {
  private let onDeinit: () -> Void

  init(onDeinit: @escaping () -> Void) {
    self.onDeinit = onDeinit
  }

  deinit {
    onDeinit()
  }
}
