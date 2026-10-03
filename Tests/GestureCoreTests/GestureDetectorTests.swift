import Foundation
import GestureCore
import XCTest

final class GestureDetectorTests: XCTestCase {
  func testPinchInCrossesRelativeThresholdAndFiresOnceUntilFullLift() {
    var detector = GestureDetector(threshold: 0.15, pinchThreshold: 0.2)
    let start = pair((0.4, 0.5), (0.6, 0.5))

    XCTAssertNil(detector.update(start))
    XCTAssertNil(detector.update(pair((0.415, 0.5), (0.585, 0.5))))
    XCTAssertEqual(detector.update(pair((0.425, 0.5), (0.575, 0.5))), .pinchIn)
    XCTAssertNil(detector.update(pair((0.44, 0.5), (0.56, 0.5))))

    XCTAssertNil(detector.update([]))
    XCTAssertNil(detector.update(start))
    XCTAssertEqual(detector.update(pair((0.43, 0.5), (0.57, 0.5))), .pinchIn)
  }

  func testSpreadOutCrossesRelativeThresholdAndFiresOnce() {
    var detector = GestureDetector(threshold: 0.15, pinchThreshold: 0.2)
    XCTAssertNil(detector.update(pair((0.4, 0.5), (0.6, 0.5))))

    XCTAssertEqual(detector.update(pair((0.37, 0.5), (0.63, 0.5))), .pinchOut)
    XCTAssertNil(detector.update(pair((0.34, 0.5), (0.66, 0.5))))
  }

  func testTranslationRotationAndSubthresholdJitterDoNotPinchOrSwipe() {
    var detector = GestureDetector(threshold: 0.15, pinchThreshold: 0.2)
    XCTAssertNil(detector.update(pair((0.4, 0.4), (0.6, 0.6))))

    XCTAssertNil(detector.update(pair((0.401, 0.401), (0.599, 0.599))))
    XCTAssertNil(detector.update(pair((0.2, 0.4), (0.4, 0.6))))
    XCTAssertNil(detector.update(pair((0.6, 0.4), (0.4, 0.6))))
  }

  func testOneFingerRadialMotionDoesNotCountAsPinch() {
    var detector = GestureDetector(threshold: 0.15, pinchThreshold: 0.2)
    XCTAssertNil(detector.update(pair((0.4, 0.5), (0.6, 0.5))))

    XCTAssertNil(detector.update(pair((0.45, 0.5), (0.6, 0.5))))
    XCTAssertNil(detector.update(pair((0.46, 0.5), (0.6, 0.5))))
  }

  func testSwipeDoesNotAlsoEmitPinchAndRequiresSupportedFingerCount() {
    var detector = GestureDetector(threshold: 0.15, pinchThreshold: 0.2)
    XCTAssertNil(detector.update(contacts(ids: [1, 2, 3], x: 0.5)))
    XCTAssertEqual(
      detector.update(contacts(ids: [1, 2, 3], x: 0.3)),
      Gesture(fingers: 3, direction: .left))
    XCTAssertNil(detector.update(contacts(ids: [1, 2, 3], x: 0.2)))
  }

  func testContactIdChangesAndInvalidCoordinatesRebaselineWithoutFiring() {
    var detector = GestureDetector(threshold: 0.15, pinchThreshold: 0.2)
    XCTAssertNil(detector.update(pair((0.4, 0.5), (0.6, 0.5), ids: [1, 2])))
    XCTAssertNil(detector.update(pair((0.43, 0.5), (0.57, 0.5), ids: [1, 3])))
    XCTAssertNil(detector.update(pair((.nan, 0.5), (0.57, 0.5), ids: [1, 3])))
    XCTAssertNil(detector.update(pair((0.43, 0.5), (0.57, 0.5), ids: [1, 3])))
  }

  func testContactCountChangeRebaselinesWithoutEmitting() {
    var detector = GestureDetector(threshold: 0.15, pinchThreshold: 0.2)
    XCTAssertNil(detector.update(pair((0.4, 0.5), (0.6, 0.5))))

    XCTAssertNil(detector.update(contacts(ids: [10, 20, 30], x: 0.8)))
    XCTAssertNil(detector.update(contacts(ids: [10, 20, 30], x: 0.8)))
  }

  func testMultiFingerCountAndIdentityChangesRebaselineBeforeFreshRecognition() {
    var countDetector = GestureDetector(threshold: 0.15, pinchThreshold: 0.2)
    XCTAssertNil(countDetector.update(radialContacts(count: 3, radius: 0.2)))
    XCTAssertNil(countDetector.update(radialContacts(count: 4, radius: 0.14)))
    XCTAssertEqual(
      countDetector.update(radialContacts(count: 4, radius: 0.17)),
      Gesture(fingers: 4, direction: .pinchOut))

    var identityDetector = GestureDetector(threshold: 0.15, pinchThreshold: 0.2)
    XCTAssertNil(identityDetector.update(radialContacts(count: 3, radius: 0.2)))
    XCTAssertNil(identityDetector.update(radialContacts(count: 3, radius: 0.14, idOffset: 10)))
    XCTAssertNil(identityDetector.update(radialContacts(count: 3, radius: 0.16, idOffset: 10)))
    XCTAssertEqual(
      identityDetector.update(radialContacts(count: 3, radius: 0.1, idOffset: 10)),
      Gesture(fingers: 3, direction: .pinchIn))
  }

  func testZeroAndVerySmallBaselinesCannotTriggerPinch() {
    for separation in [0.0, 0.01, 0.039] {
      var detector = GestureDetector(threshold: 0.15, pinchThreshold: 0.2)
      let midpoint = 0.5
      let half = separation / 2
      XCTAssertNil(detector.update(pair((midpoint - half, 0.5), (midpoint + half, 0.5))))
      XCTAssertNil(detector.update(pair((0.5, 0.5), (0.5 + separation * 0.2, 0.5))))
    }

    for radius in [0.0, 0.01, 0.019] {
      var detector = GestureDetector(threshold: 0.15, pinchThreshold: 0.2)
      XCTAssertNil(detector.update(radialContacts(count: 3, radius: radius)))
      XCTAssertNil(detector.update(radialContacts(count: 3, radius: radius * 0.5)))
    }
  }

  func testDevicesKeepIndependentRecognitionState() {
    var detectors: [UInt: GestureDetector] = [
      1: GestureDetector(threshold: 0.15, pinchThreshold: 0.2),
      2: GestureDetector(threshold: 0.15, pinchThreshold: 0.2),
    ]
    let start = pair((0.4, 0.5), (0.6, 0.5))
    XCTAssertNil(detectors[1]?.update(start))
    XCTAssertNil(detectors[2]?.update(start))

    XCTAssertEqual(detectors[1]?.update(pair((0.43, 0.5), (0.57, 0.5))), .pinchIn)
    XCTAssertNil(detectors[2]?.update(pair((0.415, 0.5), (0.585, 0.5))))
    XCTAssertEqual(detectors[2]?.update(pair((0.43, 0.5), (0.57, 0.5))), .pinchIn)
  }

  func testThreeToFiveFingerPinchesInAndOutFireOnceUntilFullLift() {
    for count in 3...5 {
      let start = radialContacts(count: count, radius: 0.2)
      var pinchInDetector = GestureDetector(threshold: 0.15, pinchThreshold: 0.2)
      XCTAssertNil(pinchInDetector.update(start))
      XCTAssertNil(pinchInDetector.update(radialContacts(count: count, radius: 0.17)))
      XCTAssertEqual(
        pinchInDetector.update(radialContacts(count: count, radius: 0.14)),
        Gesture(fingers: count, direction: .pinchIn))
      XCTAssertNil(pinchInDetector.update(radialContacts(count: count, radius: 0.12)))
      XCTAssertNil(pinchInDetector.update([]))
      XCTAssertNil(pinchInDetector.update(start))
      XCTAssertEqual(
        pinchInDetector.update(radialContacts(count: count, radius: 0.14)),
        Gesture(fingers: count, direction: .pinchIn))

      var spreadDetector = GestureDetector(threshold: 0.15, pinchThreshold: 0.2)
      XCTAssertNil(spreadDetector.update(start))
      XCTAssertNil(spreadDetector.update(radialContacts(count: count, radius: 0.23)))
      XCTAssertEqual(
        spreadDetector.update(radialContacts(count: count, radius: 0.26)),
        Gesture(fingers: count, direction: .pinchOut))
      XCTAssertNil(spreadDetector.update(radialContacts(count: count, radius: 0.3)))
      XCTAssertNil(spreadDetector.update([]))
      XCTAssertNil(spreadDetector.update(start))
      XCTAssertEqual(
        spreadDetector.update(radialContacts(count: count, radius: 0.26)),
        Gesture(fingers: count, direction: .pinchOut))
    }
  }

  func testOneFingerMotionAboveRMSThresholdDoesNotPinch() {
    let pinchThreshold = 0.2
    for count in 3...5 {
      let start = radialContacts(count: count, radius: 0.1)
      let initialRadius = rmsRadius(start)
      var detector = GestureDetector(threshold: 0.15, pinchThreshold: pinchThreshold)
      XCTAssertNil(detector.update(start))

      for scale in [1.5, 2.0, 3.0] {
        var current = start
        current[0] = Contact(
          id: current[0].id,
          x: 0.5 + (current[0].x - 0.5) * scale,
          y: 0.5 + (current[0].y - 0.5) * scale)
        let relativeRadiusChange = abs(1 - rmsRadius(current) / initialRadius)
        if scale >= 2.0 {
          XCTAssertGreaterThan(relativeRadiusChange, pinchThreshold)
        } else {
          XCTAssertLessThan(relativeRadiusChange, pinchThreshold)
        }
        XCTAssertNil(detector.update(current), "\(count) contacts, one finger scaled to \(scale)")
      }
    }
  }

  func testOneStationaryFingerDoesNotPinchWhenOthersCrossRmsThreshold() {
    let pinchThreshold = 0.2
    for count in 3...5 {
      let start = radialContacts(count: count, radius: 0.2)
      let current = start.enumerated().map { index, contact in
        guard index != 0 else { return contact }
        return Contact(
          id: contact.id,
          x: 0.5 + (contact.x - 0.5) * 0.3,
          y: 0.5 + (contact.y - 0.5) * 0.3)
      }
      let relativeRadiusChange = 1 - rmsRadius(current) / rmsRadius(start)
      XCTAssertGreaterThan(relativeRadiusChange, pinchThreshold)

      var detector = GestureDetector(threshold: 0.15, pinchThreshold: pinchThreshold)
      XCTAssertNil(detector.update(start))
      XCTAssertNil(detector.update(current), "\(count) contacts, first finger stationary")
    }
  }

  func testMultiFingerPinchRejectsTranslationRotationAndOneFingerOutlier() {
    for count in 3...5 {
      let start = radialContacts(count: count, radius: 0.2)
      var detector = GestureDetector(threshold: 0.15, pinchThreshold: 0.2)
      XCTAssertNil(detector.update(start))
      XCTAssertNil(detector.update(translated(start, x: 0.1, y: -0.05)))
      XCTAssertNil(detector.update(rotated(start)))

      var oneFingerMoved = start
      oneFingerMoved[0] = Contact(
        id: oneFingerMoved[0].id,
        x: 0.5 + (oneFingerMoved[0].x - 0.5) * 0.5,
        y: 0.5 + (oneFingerMoved[0].y - 0.5) * 0.5)
      XCTAssertNil(detector.update(oneFingerMoved))
    }
  }

  private func radialContacts(count: Int, radius: Double, idOffset: Int = 0) -> [Contact] {
    (0..<count).map { index in
      let angle = 2 * Double.pi * Double(index) / Double(count)
      return Contact(
        id: index + 1 + idOffset,
        x: 0.5 + radius * cos(angle),
        y: 0.5 + radius * sin(angle))
    }
  }

  private func rmsRadius(_ contacts: [Contact]) -> Double {
    let count = Double(contacts.count)
    let centerX = contacts.map(\.x).reduce(0, +) / count
    let centerY = contacts.map(\.y).reduce(0, +) / count
    let magnitudeSquared = contacts.reduce(0) { result, contact in
      let x = contact.x - centerX
      let y = contact.y - centerY
      return result + x * x + y * y
    }
    return sqrt(magnitudeSquared / count)
  }

  private func translated(_ contacts: [Contact], x: Double, y: Double) -> [Contact] {
    contacts.map { Contact(id: $0.id, x: $0.x + x, y: $0.y + y) }
  }

  private func rotated(_ contacts: [Contact]) -> [Contact] {
    contacts.map { contact in
      Contact(id: contact.id, x: 1 - contact.y, y: contact.x)
    }
  }

  private func pair(
    _ first: (Double, Double), _ second: (Double, Double), ids: [Int] = [10, 20]
  ) -> [Contact] {
    [
      Contact(id: ids[0], x: first.0, y: first.1),
      Contact(id: ids[1], x: second.0, y: second.1),
    ]
  }

  private func contacts(ids: [Int], x: Double, y: Double = 0.5) -> [Contact] {
    ids.map { Contact(id: $0, x: x, y: y) }
  }
}
