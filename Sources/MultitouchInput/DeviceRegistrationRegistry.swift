import Foundation

struct InputDeviceDescriptor: Equatable, Hashable {
  /// Stable value identity from the private API; unlike `handle`, it survives list rewrapping.
  let identity: String
  let handle: UInt

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.identity == rhs.identity
  }

  func hash(into hasher: inout Hasher) {
    hasher.combine(identity)
  }
}

struct InputDeviceSnapshot {
  let devices: [InputDeviceDescriptor]
  let supportsStableIdentity: Bool
  let lifetime: AnyObject?

  init(
    devices: [InputDeviceDescriptor],
    supportsStableIdentity: Bool = true,
    lifetime: AnyObject? = nil
  ) {
    self.devices = devices
    self.supportsStableIdentity = supportsStableIdentity
    self.lifetime = lifetime
  }
}

struct DeviceRegistration: Equatable {
  let descriptor: InputDeviceDescriptor
  let token: UInt
}

struct DeviceReconciliation {
  let added: [DeviceRegistration]
  let removed: [DeviceRegistration]
}

enum DeviceSnapshotError: Error {
  case duplicateIdentity
}

struct DeviceRegistrationRegistry {
  private(set) var registrationsByIdentity: [String: DeviceRegistration] = [:]
  private var nextToken: UInt = 1

  var registrations: [DeviceRegistration] {
    registrationsByIdentity.values.sorted {
      $0.descriptor.identity < $1.descriptor.identity
    }
  }

  var activeTokens: Set<UInt> {
    Set(registrationsByIdentity.values.map(\.token))
  }

  func registration(for identity: String) -> DeviceRegistration? {
    registrationsByIdentity[identity]
  }

  mutating func reconcile(
    _ snapshot: [InputDeviceDescriptor],
    forceRebind: Bool = false
  ) throws -> DeviceReconciliation {
    var discovered: [String: InputDeviceDescriptor] = [:]
    for descriptor in snapshot {
      guard discovered.updateValue(descriptor, forKey: descriptor.identity) == nil else {
        throw DeviceSnapshotError.duplicateIdentity
      }
    }

    let removed = registrations.filter { registration in
      forceRebind || discovered[registration.descriptor.identity] != registration.descriptor
    }
    for registration in removed {
      registrationsByIdentity.removeValue(forKey: registration.descriptor.identity)
    }

    var added: [DeviceRegistration] = []
    for descriptor in discovered.values.sorted(by: {
      $0.identity < $1.identity
    }) where forceRebind || registrationsByIdentity[descriptor.identity] == nil {
      let registration = DeviceRegistration(
        descriptor: descriptor,
        token: allocateToken())
      registrationsByIdentity[descriptor.identity] = registration
      added.append(registration)
    }

    return DeviceReconciliation(added: added, removed: removed)
  }

  mutating func createRegistration(for descriptor: InputDeviceDescriptor) -> DeviceRegistration? {
    guard registrationsByIdentity[descriptor.identity] == nil else { return nil }
    let registration = DeviceRegistration(descriptor: descriptor, token: allocateToken())
    registrationsByIdentity[descriptor.identity] = registration
    return registration
  }

  mutating func remove(_ registration: DeviceRegistration) {
    guard registrationsByIdentity[registration.descriptor.identity] == registration else { return }
    registrationsByIdentity.removeValue(forKey: registration.descriptor.identity)
  }

  mutating func removeAll() -> [DeviceRegistration] {
    let removed = registrations
    registrationsByIdentity.removeAll(keepingCapacity: true)
    return removed
  }

  private mutating func allocateToken() -> UInt {
    while registrationsByIdentity.values.contains(where: { $0.token == nextToken }) {
      nextToken = nextToken == .max ? 1 : nextToken + 1
    }
    let token = nextToken
    nextToken = nextToken == .max ? 1 : nextToken + 1
    return token
  }
}
