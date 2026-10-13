import CoreGraphics
import GestureCLIPolicy
import GestureCore

/// Reads only current modifier flags from the active login session; it does not capture key events.
struct CoreGraphicsModifierStateSampler: ModifierStateSampling {
  func sample() -> ModifierSample {
    Self.modifierSample(for: CGEventSource.flagsState(.combinedSessionState))
  }

  private static let deviceModifierMappings:
    [(deviceFlag: CGEventFlags, canonicalFlag: CGEventFlags)] = [
      (CGEventFlags(rawValue: 0x0000_0008), .maskCommand),  // NX_DEVICELCMDKEYMASK
      (CGEventFlags(rawValue: 0x0000_0010), .maskCommand),  // NX_DEVICERCMDKEYMASK
      (CGEventFlags(rawValue: 0x0000_0020), .maskAlternate),  // NX_DEVICELALTKEYMASK
      (CGEventFlags(rawValue: 0x0000_0040), .maskAlternate),  // NX_DEVICERALTKEYMASK
      (CGEventFlags(rawValue: 0x0000_0001), .maskControl),  // NX_DEVICELCTLKEYMASK
      (CGEventFlags(rawValue: 0x0000_2000), .maskControl),  // NX_DEVICERCTLKEYMASK
      (CGEventFlags(rawValue: 0x0000_0002), .maskShift),  // NX_DEVICELSHIFTKEYMASK
      (CGEventFlags(rawValue: 0x0000_0004), .maskShift),  // NX_DEVICERSHIFTKEYMASK
    ]

  static func modifierSample(for flags: CGEventFlags) -> ModifierSample {
    let supportedFlags: CGEventFlags = [
      .maskCommand, .maskAlternate, .maskControl, .maskShift,
    ]
    var recognizedFlags = supportedFlags

    for mapping in deviceModifierMappings where flags.contains(mapping.deviceFlag) {
      guard flags.contains(mapping.canonicalFlag) else { return .unknown }
      recognizedFlags.formUnion(mapping.deviceFlag)
    }

    // IOLLEvent.h defines 0x80 as stateless AlphaShift (also deprecated stylus proximity).
    let deviceAlphaShiftFlag = CGEventFlags(rawValue: 0x0000_0080)
    if flags.contains(deviceAlphaShiftFlag) {
      guard flags.contains(.maskAlphaShift) else { return .unknown }
      recognizedFlags.formUnion(deviceAlphaShiftFlag)
    }

    // Caps Lock is toggled state; event coalescing is metadata. Neither changes the held modifier set.
    let ignoredEventFlags: CGEventFlags = [.maskAlphaShift, .maskNonCoalesced]
    guard flags.subtracting(recognizedFlags).subtracting(ignoredEventFlags).isEmpty else {
      return .unknown
    }

    var modifiers: [GestureModifier] = []
    if flags.contains(.maskCommand) { modifiers.append(.command) }
    if flags.contains(.maskAlternate) { modifiers.append(.option) }
    if flags.contains(.maskControl) { modifiers.append(.control) }
    if flags.contains(.maskShift) { modifiers.append(.shift) }
    return .known(ModifierSet(modifiers))
  }
}
