import GestureCLIPolicy
import GestureCore

enum GestureOutputFormatter {
  static func describe(
    gesture: Gesture,
    modifiers: ModifierSample,
    actionContext: String
  ) -> String {
    "\(gesture.displayName) (\(modifiers.displayName))\(actionContext)"
  }
}
