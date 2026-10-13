import GestureCore
import XCTest

@testable import GestureCLIPolicy

final class ModifierSequenceTrackerTests: XCTestCase {
  func testModifierChangeCancelsSequenceUntilFullLiftThenNextSequenceRearms() {
    var tracker = ModifierSequenceTracker()
    let command = ModifierSample.known(ModifierSet([.command]))
    let commandShift = ModifierSample.known(ModifierSet([.command, .shift]))
    let shift = ModifierSample.known(ModifierSet([.shift]))

    XCTAssertEqual(tracker.observe(device: 7, contactCount: 1, sample: command), command)
    XCTAssertEqual(tracker.observe(device: 7, contactCount: 3, sample: commandShift), .unknown)
    XCTAssertEqual(tracker.observe(device: 7, contactCount: 3, sample: command), .unknown)
    XCTAssertNil(tracker.observe(device: 7, contactCount: 0, sample: .unknown))
    XCTAssertEqual(tracker.observe(device: 7, contactCount: 1, sample: shift), shift)
  }

  func testUnknownAtFirstContactCancelsUntilFullLift() {
    var tracker = ModifierSequenceTracker()

    XCTAssertEqual(tracker.observe(device: 1, contactCount: 2, sample: .unknown), .unknown)
    XCTAssertEqual(
      tracker.observe(device: 1, contactCount: 2, sample: .known(.none)), .unknown)
    XCTAssertNil(tracker.observe(device: 1, contactCount: 0, sample: .unknown))
    XCTAssertEqual(
      tracker.observe(device: 1, contactCount: 2, sample: .known(.none)), .known(.none))
  }

  func testModifierSequencesAreIndependentPerDevice() {
    var tracker = ModifierSequenceTracker()
    let command = ModifierSample.known(ModifierSet([.command]))
    let shift = ModifierSample.known(ModifierSet([.shift]))

    XCTAssertEqual(tracker.observe(device: 1, contactCount: 3, sample: command), command)
    XCTAssertEqual(tracker.observe(device: 2, contactCount: 3, sample: shift), shift)
    XCTAssertEqual(tracker.observe(device: 1, contactCount: 3, sample: shift), .unknown)
    XCTAssertEqual(tracker.observe(device: 2, contactCount: 3, sample: shift), shift)
  }
}
