import AppKit
import GestureCLIPolicy
import GestureInfrastructure

enum MenuBarBranding {
  static let productName = "Cafuné"

  static func tooltip(for accessibilityLabel: String) -> String {
    "\(productName) — \(accessibilityLabel)"
  }
}

@MainActor
final class MenuBarQuitAction: NSObject {
  private let onQuit: () -> Void
  let menuItem: NSMenuItem

  init(onQuit: @escaping () -> Void) {
    self.onQuit = onQuit
    menuItem = NSMenuItem(
      title: "Quit \(MenuBarBranding.productName)", action: #selector(quit), keyEquivalent: "")
    super.init()
    menuItem.target = self
  }

  @objc func quit() {
    onQuit()
  }
}

@MainActor
final class MenuBarControl: NSObject, NSMenuDelegate {
  private let actionPolicy: GestureActionPolicy
  private let appGesturePolicy: AppGesturePolicy
  private var hasAppBindings: Bool
  private let reloadPolicy: ConfigurationReloadPolicy
  private let reloadAdapter: ConfigurationReloadAdapter
  private let onSuccessfulReload: () -> Void
  private let quitAction: MenuBarQuitAction
  private let statusItem: NSStatusItem
  private let stateItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
  private let toggleItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
  private let appToggleItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
  private let reloadItem = NSMenuItem(title: "Reload configuration", action: nil, keyEquivalent: "")
  private let reloadFeedbackItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")

  init(
    actionPolicy: GestureActionPolicy,
    appGesturePolicy: AppGesturePolicy,
    hasAppBindings: Bool,
    reloadPolicy: ConfigurationReloadPolicy,
    reloadAdapter: ConfigurationReloadAdapter,
    onSuccessfulReload: @escaping () -> Void,
    onQuit: @escaping () -> Void
  ) {
    precondition(actionPolicy.showsMenuBarControl && reloadPolicy.canReload)
    self.actionPolicy = actionPolicy
    self.appGesturePolicy = appGesturePolicy
    self.hasAppBindings = hasAppBindings
    self.reloadPolicy = reloadPolicy
    self.reloadAdapter = reloadAdapter
    self.onSuccessfulReload = onSuccessfulReload
    quitAction = MenuBarQuitAction(onQuit: onQuit)
    statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    super.init()

    stateItem.isEnabled = false
    toggleItem.target = self
    toggleItem.action = #selector(toggleActions)
    appToggleItem.target = self
    appToggleItem.action = #selector(toggleAppGestures)
    reloadItem.target = self
    reloadItem.action = #selector(reloadConfiguration)
    reloadFeedbackItem.isEnabled = false

    let menu = NSMenu()
    menu.delegate = self
    menu.addItem(stateItem)
    menu.addItem(.separator())
    menu.addItem(toggleItem)
    menu.addItem(appToggleItem)
    menu.addItem(.separator())
    menu.addItem(reloadItem)
    menu.addItem(reloadFeedbackItem)
    menu.addItem(.separator())
    menu.addItem(quitAction.menuItem)
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

  @objc private func toggleAppGestures() {
    appGesturePolicy.setEnabled(!appGesturePolicy.isEnabled)
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
          let hasAppBindings =
            self.reloadPolicy.activeConfiguration?.bindings.contains(
              where: { $0.app != nil }) == true
          self.appGesturePolicy.setHasAppScopedBindings(hasAppBindings)
          self.onSuccessfulReload()
          self.hasAppBindings = hasAppBindings
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
    appToggleItem.title =
      appGesturePolicy.isEnabled
      ? "Disable app-specific gestures" : "Enable app-specific gestures"
    appToggleItem.state = appGesturePolicy.isEnabled ? .on : .off
    appToggleItem.isHidden = !hasAppBindings

    let reloadPresentation = ConfigurationReloadPresentation(
      state: reloadPolicy.state, canReload: reloadPolicy.canReload)
    reloadItem.isEnabled = reloadPresentation.reloadIsEnabled
    reloadFeedbackItem.title = reloadPresentation.feedbackMessage ?? ""
    reloadFeedbackItem.isHidden = reloadPresentation.feedbackMessage == nil

    guard let button = statusItem.button else { return }
    button.setAccessibilityLabel(presentation.accessibilityLabel)
    button.toolTip = MenuBarBranding.tooltip(for: presentation.accessibilityLabel)
    button.image = MenuBarIcon.image(
      isPaused: actionPolicy.state == .paused,
      accessibilityDescription: presentation.accessibilityLabel)
    button.title = ""
  }
}
