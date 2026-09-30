import Foundation
import GestureCore
import MultitouchBridge

/// Owns the private bridge boundary and copies callback-owned contacts before returning.
public enum MultitouchInput {
  private static let handlerLock = NSLock()
  private static var frameHandler: ((UInt, [Contact]) -> Void)?

  public static func start(onFrame: @escaping (UInt, [Contact]) -> Void) -> String? {
    handlerLock.lock()
    frameHandler = onFrame
    handlerLock.unlock()
    guard let error = AGStart(receiveFrame) else { return nil }
    clearHandler()
    return String(cString: error)
  }

  public static func stop() {
    AGStop()
    clearHandler()
  }

  private static let receiveFrame: AGFrameCallback = { device, raw, count in
    let contacts = (0..<Int(count)).map { index -> Contact in
      let point = raw![index]
      return Contact(id: Int(point.id), x: Double(point.x), y: Double(point.y))
    }
    handlerLock.lock()
    let handler = frameHandler
    handlerLock.unlock()
    handler?(UInt(device), contacts)
  }

  private static func clearHandler() {
    handlerLock.lock()
    frameHandler = nil
    handlerLock.unlock()
  }
}
