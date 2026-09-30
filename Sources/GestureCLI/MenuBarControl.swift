import AppKit
import GestureCLIPolicy

@MainActor
final class MenuBarControl: NSObject, NSMenuDelegate {
  private let actionPolicy: GestureActionPolicy
  private let statusItem: NSStatusItem
  private let stateItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
  private let toggleItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")

  init(actionPolicy: GestureActionPolicy) {
    precondition(actionPolicy.showsMenuBarControl)
    self.actionPolicy = actionPolicy
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    super.init()

    stateItem.isEnabled = false
    toggleItem.target = self
    toggleItem.action = #selector(toggleActions)

    let menu = NSMenu()
    menu.delegate = self
    menu.addItem(stateItem)
    menu.addItem(.separator())
    menu.addItem(toggleItem)
    statusItem.menu = menu
    updatePresentation()
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    updatePresentation()
  }

  @objc private func toggleActions() {
    actionPolicy.setActionsEnabled(actionPolicy.state != .enabled)
    updatePresentation()
  }

  private func updatePresentation() {
    let presentation = GestureActionPresentation(state: actionPolicy.state)
    stateItem.title = presentation.statusTitle
    toggleItem.title = presentation.toggleTitle ?? ""
    toggleItem.state = presentation.toggleIsChecked ? .on : .off
    toggleItem.isHidden = presentation.toggleTitle == nil

    guard let button = statusItem.button else { return }
    button.setAccessibilityLabel(presentation.accessibilityLabel)
    button.toolTip = presentation.accessibilityLabel

    let symbolName = actionPolicy.state == .enabled ? "hand.point.up.left.fill" : "hand.raised.fill"
    if let image = NSImage(
      systemSymbolName: symbolName, accessibilityDescription: presentation.accessibilityLabel)
    {
      image.isTemplate = true
      button.image = image
      button.title = ""
    } else {
      button.image = nil
      button.title = actionPolicy.state == .enabled ? "On" : "Paused"
    }
  }
}
