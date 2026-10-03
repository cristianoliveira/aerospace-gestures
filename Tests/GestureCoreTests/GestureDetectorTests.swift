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

  func testZeroAndVerySmallBaselineSeparationCannotTriggerPinch() {
    for separation in [0.0, 0.01, 0.039] {
      var detector = GestureDetector(threshold: 0.15, pinchThreshold: 0.2)
      let midpoint = 0.5
      let half = separation / 2
      XCTAssertNil(detector.update(pair((midpoint - half, 0.5), (midpoint + half, 0.5))))
      XCTAssertNil(detector.update(pair((0.5, 0.5), (0.5 + separation * 0.2, 0.5))))
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
