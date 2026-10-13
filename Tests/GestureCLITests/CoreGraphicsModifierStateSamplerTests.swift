import CoreGraphics
import GestureCLIPolicy
import GestureCore
import XCTest

@testable import GestureCLI

final class CoreGraphicsModifierStateSamplerTests: XCTestCase {
  func testMapsSupportedSessionFlagsToCanonicalModifierSet() {
    let flags: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]

    XCTAssertEqual(
      CoreGraphicsModifierStateSampler.modifierSample(for: flags),
      .known(ModifierSet([.command, .option, .control, .shift])))
  }

  func testNoFlagsMeansNoModifiers() {
    XCTAssertEqual(
      CoreGraphicsModifierStateSampler.modifierSample(for: []), .known(.none))
  }

  func testObservationOutputIncludesModifiersForSafeModesAndUnknownState() {
    let gesture = Gesture(fingers: 3, direction: .left)
    let modifiers = ModifierSample.known(ModifierSet([.command, .option]))

    XCTAssertEqual(
      GestureOutputFormatter.describe(
        gesture: gesture, modifiers: modifiers, actionContext: " (listen only)"),
      "3-finger left (Command+Option) (listen only)")
    XCTAssertEqual(
      GestureOutputFormatter.describe(
        gesture: gesture, modifiers: .unknown, actionContext: " (listen only)"),
      "3-finger left (modifier state unknown) (listen only)")
  }

  func testIgnoresNonCoalescedEventMetadata() {
    XCTAssertEqual(
      CoreGraphicsModifierStateSampler.modifierSample(for: .maskNonCoalesced), .known(.none))
  }

  func testUnsupportedFlagsFailClosedInsteadOfBecomingNoModifiers() {
    XCTAssertEqual(
      CoreGraphicsModifierStateSampler.modifierSample(for: .maskSecondaryFn), .unknown)
    XCTAssertEqual(
      CoreGraphicsModifierStateSampler.modifierSample(for: .maskAlphaShift), .unknown)
  }
}
