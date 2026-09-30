public struct GestureActionPresentation: Equatable {
  public let statusTitle: String
  public let accessibilityLabel: String
  public let toggleTitle: String?
  public let toggleIsChecked: Bool

  public init(state: GestureActionState) {
    switch state {
    case .enabled:
      statusTitle = "Actions enabled"
      accessibilityLabel = "Gesture actions enabled"
      toggleTitle = "Disable actions"
      toggleIsChecked = true
    case .paused:
      statusTitle = "Actions paused — listener active"
      accessibilityLabel = "Gesture actions paused; listener remains active"
      toggleTitle = "Enable actions"
      toggleIsChecked = false
    case .unavailable:
      statusTitle = "Actions unavailable"
      accessibilityLabel = "Gesture actions unavailable in listen or dry-run mode"
      toggleTitle = nil
      toggleIsChecked = false
    }
  }
}
