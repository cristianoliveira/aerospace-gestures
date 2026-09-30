import AppKit
import GestureCLIPolicy
import GestureInfrastructure

@MainActor
final class MenuBarControl: NSObject, NSMenuDelegate {
  private let actionPolicy: GestureActionPolicy
  private let reloadPolicy: ConfigurationReloadPolicy
  private let reloadAdapter: ConfigurationReloadAdapter
  private let onSuccessfulReload: () -> Void
  private let statusItem: NSStatusItem
  private let stateItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
  private let toggleItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
  private let reloadItem = NSMenuItem(title: "Reload configuration", action: nil, keyEquivalent: "")
  private let reloadFeedbackItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")

  init(
    actionPolicy: GestureActionPolicy,
    reloadPolicy: ConfigurationReloadPolicy,
    reloadAdapter: ConfigurationReloadAdapter,
    onSuccessfulReload: @escaping () -> Void
  ) {
    precondition(actionPolicy.showsMenuBarControl && reloadPolicy.canReload)
    self.actionPolicy = actionPolicy
    self.reloadPolicy = reloadPolicy
    self.reloadAdapter = reloadAdapter
    self.onSuccessfulReload = onSuccessfulReload
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    super.init()

    stateItem.isEnabled = false
    toggleItem.target = self
    toggleItem.action = #selector(toggleActions)
    reloadItem.target = self
    reloadItem.action = #selector(reloadConfiguration)
    reloadFeedbackItem.isEnabled = false

    let menu = NSMenu()
    menu.delegate = self
    menu.addItem(stateItem)
    menu.addItem(.separator())
    menu.addItem(toggleItem)
    menu.addItem(.separator())
    menu.addItem(reloadItem)
    menu.addItem(reloadFeedbackItem)
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

  @objc private func reloadConfiguration() {
    guard let token = reloadPolicy.beginReload() else { return }
    updatePresentation()

    let adapter = reloadAdapter
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      do {
        let configuration = try adapter.load()
        DispatchQueue.main.async {
          guard let self,
            self.reloadPolicy.completeReload(token, with: .success(configuration))
          else { return }
          self.onSuccessfulReload()
          self.updatePresentation()
        }
      } catch {
        let message = String(describing: error)
        DispatchQueue.main.async {
          guard let self,
            self.reloadPolicy.completeReload(token, with: .failure(message))
          else { return }
          self.updatePresentation()
        }
      }
    }
  }

  private func updatePresentation() {
    let presentation = GestureActionPresentation(state: actionPolicy.state)
    stateItem.title = presentation.statusTitle
    toggleItem.title = presentation.toggleTitle ?? ""
    toggleItem.state = presentation.toggleIsChecked ? .on : .off
    toggleItem.isHidden = presentation.toggleTitle == nil

    let reloadPresentation = ConfigurationReloadPresentation(
      state: reloadPolicy.state, canReload: reloadPolicy.canReload)
    reloadItem.isEnabled = reloadPresentation.reloadIsEnabled
    reloadFeedbackItem.title = reloadPresentation.feedbackMessage ?? ""
    reloadFeedbackItem.isHidden = reloadPresentation.feedbackMessage == nil

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
