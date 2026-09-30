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

  public static func start(onFrame: @escaping (UInt, [Contact]) -> Void) -> String? {
    controller.start(onFrame: onFrame)
  }

  public static func stop() {
    controller.stop()
  }

  private static let receiveFrame: AGFrameCallback = { device, raw, count in
    let contacts = (0..<Int(count)).map { index -> Contact in
      let point = raw![index]
      return Contact(id: Int(point.id), x: Double(point.x), y: Double(point.y))
    }
    controller.receive(device: UInt(device), contacts: contacts)
  }
}

final class MultitouchInputController {
  private let startBridge: () -> String?
  private let stopBridge: () -> Void
  private let handlerLock = NSLock()
  private var frameHandler: ((UInt, [Contact]) -> Void)?

  init(startBridge: @escaping () -> String?, stopBridge: @escaping () -> Void) {
    self.startBridge = startBridge
    self.stopBridge = stopBridge
  }

  func start(onFrame: @escaping (UInt, [Contact]) -> Void) -> String? {
    handlerLock.lock()
    guard frameHandler == nil else {
      handlerLock.unlock()
      return "Multitouch listener already started"
    }
    frameHandler = onFrame
    handlerLock.unlock()

    guard let error = startBridge() else { return nil }
    clearHandler()
    return error
  }

  func stop() {
    clearHandler()
    stopBridge()
  }

  func receive(device: UInt, contacts: [Contact]) {
    handlerLock.lock()
    let handler = frameHandler
    handlerLock.unlock()
    handler?(device, contacts)
  }

  private func clearHandler() {
    handlerLock.lock()
    frameHandler = nil
    handlerLock.unlock()
  }
}
