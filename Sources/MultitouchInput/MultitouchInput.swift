import Foundation
import GestureCore
import MultitouchBridge

/// Owns the private bridge boundary and copies callback-owned contacts before returning.
/// Call start/stop on the main thread. Only one listener may be active; in-flight callbacks may
/// complete after stop returns.
public enum MultitouchInput {
  private static let controller = MultitouchInputController(
    startBridge: {
      guard let error = AGStart(receiveFrame) else { return nil }
      return String(cString: error)
    },
    stopBridge: { AGStop() })

  public static func start(onFrame: @escaping (UInt, UInt32, [Contact]) -> Void) -> String? {
    controller.start(onFrame: onFrame)
  }

  public static func stop() {
    controller.stop()
  }

  private static let receiveFrame: AGFrameCallback = { device, frame, raw, count in
    let contacts = (0..<Int(count)).map { index -> Contact in
      let point = raw![index]
      return Contact(id: Int(point.id), x: Double(point.x), y: Double(point.y))
    }
    controller.receive(device: UInt(device), frame: frame, contacts: contacts)
  }
}

final class MultitouchInputController {
  private let startBridge: () -> String?
  private let stopBridge: () -> Void
  private let handlerLock = NSLock()
  // Keep sequence validation and handler submission atomic across concurrent callbacks.
  private let frameDeliveryLock = NSLock()
  private var frameHandler: ((UInt, UInt32, [Contact]) -> Void)?
  private var lastFrameByDevice: [UInt: UInt32] = [:]

  init(startBridge: @escaping () -> String?, stopBridge: @escaping () -> Void) {
    self.startBridge = startBridge
    self.stopBridge = stopBridge
  }

  func start(onFrame: @escaping (UInt, UInt32, [Contact]) -> Void) -> String? {
    handlerLock.lock()
    guard frameHandler == nil else {
      handlerLock.unlock()
      return "Multitouch listener already started"
    }
    frameHandler = onFrame
    handlerLock.unlock()

    frameDeliveryLock.lock()
    lastFrameByDevice.removeAll(keepingCapacity: true)
    frameDeliveryLock.unlock()

    guard let error = startBridge() else { return nil }
    clearHandler()
    return error
  }

  func stop() {
    clearHandler()
    stopBridge()
  }

  func receive(device: UInt, frame: UInt32, contacts: [Contact]) {
    handlerLock.lock()
    let handler = frameHandler
    handlerLock.unlock()
    guard let handler else { return }

    frameDeliveryLock.lock()
    defer { frameDeliveryLock.unlock() }
    if let previousFrame = lastFrameByDevice[device], !Self.isNewer(frame, than: previousFrame) {
      return
    }
    lastFrameByDevice[device] = frame
    handler(device, frame, contacts)
  }

  private static func isNewer(_ frame: UInt32, than previousFrame: UInt32) -> Bool {
    // Unsigned subtraction handles wrap; the half-range test rejects stale frames.
    let distance = frame &- previousFrame
    return distance > 0 && distance < 0x8000_0000
  }

  private func clearHandler() {
    handlerLock.lock()
    frameHandler = nil
    handlerLock.unlock()
  }
}
