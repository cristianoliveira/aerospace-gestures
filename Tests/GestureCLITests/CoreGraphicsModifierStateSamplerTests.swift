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

  func testIgnoresObservedReservedSessionBit() {
    let flags: CGEventFlags = [
      .maskCommand, .maskNonCoalesced, CGEventFlags(rawValue: 0x8),
    ]

    XCTAssertEqual(
      CoreGraphicsModifierStateSampler.modifierSample(for: flags),
      .known(ModifierSet([.command])))
  }

  func testOtherUnknownFlagsFailClosed() {
    let flags: [CGEventFlags] = [
      [.maskCommand, .maskHelp],
      [.maskCommand, .maskNumericPad],
      [.maskCommand, CGEventFlags(rawValue: 0x10)],
    ]

    for flagSet in flags {
      XCTAssertEqual(CoreGraphicsModifierStateSampler.modifierSample(for: flagSet), .unknown)
    }
  }

  func testCapsLockStateIsIgnoredButUnsupportedFnFailsClosed() {
    XCTAssertEqual(
      CoreGraphicsModifierStateSampler.modifierSample(for: .maskAlphaShift), .known(.none))
    XCTAssertEqual(
      CoreGraphicsModifierStateSampler.modifierSample(for: [.maskAlphaShift, .maskCommand]),
      .known(ModifierSet([.command])))
    XCTAssertEqual(
      CoreGraphicsModifierStateSampler.modifierSample(for: .maskSecondaryFn), .unknown)
    XCTAssertEqual(
      CoreGraphicsModifierStateSampler.modifierSample(for: [.maskCommand, .maskSecondaryFn]),
      .unknown)
  }
}
