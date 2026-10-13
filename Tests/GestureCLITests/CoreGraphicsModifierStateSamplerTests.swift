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

  func testMapsEachDeviceSpecificModifierBitWithItsCanonicalMask() {
    let deviceModifierCases: [(rawValue: UInt64, mask: CGEventFlags, modifier: GestureModifier)] = [
      (0x0000_0008, .maskCommand, .command),
      (0x0000_0010, .maskCommand, .command),
      (0x0000_0020, .maskAlternate, .option),
      (0x0000_0040, .maskAlternate, .option),
      (0x0000_0001, .maskControl, .control),
      (0x0000_2000, .maskControl, .control),
      (0x0000_0002, .maskShift, .shift),
      (0x0000_0004, .maskShift, .shift),
    ]

    for entry in deviceModifierCases {
      let flags = CGEventFlags(rawValue: entry.rawValue)
        .union(entry.mask)
        .union(.maskNonCoalesced)

      XCTAssertEqual(
        CoreGraphicsModifierStateSampler.modifierSample(for: flags),
        .known(ModifierSet([entry.modifier])),
        "device-specific flag 0x\(String(entry.rawValue, radix: 16))")
    }
  }

  func testMapsBothSidesOfAllDeviceSpecificModifiersTogether() {
    let deviceFlags = CGEventFlags(rawValue: 0x0000_007f | 0x0000_2000)
    let canonicalFlags: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]

    XCTAssertEqual(
      CoreGraphicsModifierStateSampler.modifierSample(for: deviceFlags.union(canonicalFlags)),
      .known(ModifierSet([.command, .option, .control, .shift])))
  }

  func testOrphanDeviceModifierFlagsFailClosed() {
    let orphanBits: [UInt64] = [
      0x0000_0001, 0x0000_0002, 0x0000_0004, 0x0000_0008, 0x0000_0010,
      0x0000_0020, 0x0000_0040, 0x0000_0080, 0x0000_2000,
    ]

    for bit in orphanBits {
      XCTAssertEqual(
        CoreGraphicsModifierStateSampler.modifierSample(for: CGEventFlags(rawValue: bit)),
        .unknown,
        "orphan device-specific bit 0x\(String(bit, radix: 16))")
    }
  }

  func testOtherUnknownFlagsFailClosed() {
    let flags: [CGEventFlags] = [
      [.maskCommand, .maskHelp],
      [.maskCommand, .maskNumericPad],
      [.maskCommand, .maskSecondaryFn],
      [.maskCommand, CGEventFlags(rawValue: 0x0000_0400)],
    ]

    for flagSet in flags {
      XCTAssertEqual(CoreGraphicsModifierStateSampler.modifierSample(for: flagSet), .unknown)
    }
  }

  func testCapsLockStateIsIgnoredButUnsupportedFnFailsClosed() {
    XCTAssertEqual(
      CoreGraphicsModifierStateSampler.modifierSample(for: .maskAlphaShift), .known(.none))
    XCTAssertEqual(
      CoreGraphicsModifierStateSampler.modifierSample(
        for: [.maskAlphaShift, .maskCommand, CGEventFlags(rawValue: 0x0000_0080)]),
      .known(ModifierSet([.command])))
    XCTAssertEqual(
      CoreGraphicsModifierStateSampler.modifierSample(for: .maskSecondaryFn), .unknown)
    XCTAssertEqual(
      CoreGraphicsModifierStateSampler.modifierSample(for: [.maskCommand, .maskSecondaryFn]),
      .unknown)
  }
}
