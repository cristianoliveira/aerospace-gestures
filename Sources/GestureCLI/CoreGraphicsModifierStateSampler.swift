import CoreGraphics
import GestureCLIPolicy
import GestureCore

/// Reads only current modifier flags from the active login session; it does not capture key events.
struct CoreGraphicsModifierStateSampler: ModifierStateSampling {
  func sample() -> ModifierSample {
    Self.modifierSample(for: CGEventSource.flagsState(.combinedSessionState))
  }

  static func modifierSample(for flags: CGEventFlags) -> ModifierSample {
    let supportedFlags: CGEventFlags = [
      .maskCommand, .maskAlternate, .maskControl, .maskShift,
    ]
    // Caps Lock is toggled state; event coalescing is metadata. Neither changes the held modifier set.
    // combinedSessionState also reports reserved bit 0x8 with Command on the tested OS.
    let ignoredEventFlags: CGEventFlags = [
      .maskAlphaShift, .maskNonCoalesced, CGEventFlags(rawValue: 0x8),
    ]
    guard flags.subtracting(supportedFlags).subtracting(ignoredEventFlags).isEmpty else {
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
