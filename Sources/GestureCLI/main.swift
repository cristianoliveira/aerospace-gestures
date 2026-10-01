import AppKit
import Darwin
import Foundation
import GestureCLIPolicy
import GestureCore
import GestureInfrastructure
import MultitouchInput

let commandName = "aerospace-gestures"

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(
    Data("Error: \(message)\nRun aerospace-gestures --help for usage and recovery steps.\n".utf8))
  exit(1)
}

func loadConfiguration(
  at url: URL, startupDiagnostics: StartupDiagnosticStore? = nil
) -> Configuration {
  do {
    let configuration = try ConfigurationFile.load(at: url)
    try ConfigurationDecision.validateExecutables(in: configuration) {
      FileManager.default.isExecutableFile(atPath: $0)
    }
    return configuration
  } catch let error as ConfigurationFileError {
    if case .cannotRead = error, !FileManager.default.fileExists(atPath: url.path) {
      try? startupDiagnostics?.record(.configurationValidationFailed)
      fail(CLIConfigurationFailure.missing(at: url))
    }
    try? startupDiagnostics?.record(.configurationValidationFailed)
    fail("\(error)")
  } catch {
    try? startupDiagnostics?.record(.configurationValidationFailed)
    fail(CLIConfigurationFailure.invalid(at: url, reason: error))
  }
}

let environment = CLIEnvironment(
  values: ProcessInfo.processInfo.environment,
  homeDirectory: FileManager.default.homeDirectoryForCurrentUser,
  currentDirectory: URL(
    fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true))
let request: CLIRequest
do {
  request = try CLIRequest.parse(Array(CommandLine.arguments.dropFirst()), in: environment)
} catch {
  fail("\(error)")
}
let managedStartupDiagnostics: StartupDiagnosticStore? =
  ProcessInfo.processInfo.environment["AEROSPACE_GESTURES_MANAGED"] == "1"
  ? StartupDiagnosticStore(
    fileURL: environment.homeDirectory
      .appendingPathComponent("Library/Application Support/aerospace-gestures", isDirectory: true)
      .appendingPathComponent("startup-diagnostic.log"),
    rootURL: environment.homeDirectory)
  : nil

switch request {
case .version:
  print(CLIVersion.current)
  exit(0)
case .help(let topic):
  print(
    CLIHelp.text(
      for: topic,
      defaultConfigurationURL: ConfigurationPath.resolve(explicitPath: nil, in: environment)))
  exit(0)
case .initialize(let configurationURL):
  do {
    try ConfigurationFile.initializeDefault(at: configurationURL)
    print("Created configuration: \(configurationURL.path)")
    exit(0)
  } catch {
    fail("\(error). Existing files are never replaced; check the path or initialize another path.")
  }
case .check(let configurationURL):
  let configuration = loadConfiguration(at: configurationURL)
  print("Configuration valid: \(configuration.bindings.count) bindings")
  exit(0)
case .service(let action):
  let executableURL = environment.homeDirectory
    .appendingPathComponent(".local/bin/aerospace-gestures")
  let paths = LaunchAgentPaths(
    homeDirectory: environment.homeDirectory,
    executableURL: executableURL,
    configurationURL: ConfigurationPath.resolve(explicitPath: nil, in: environment),
    uid: getuid())
  let service = LaunchAgentService(paths: paths)
  do {
    if action == .status {
      print(try service.status())
      exit(0)
    }
    let result: ServiceOperationResult
    switch action {
    case .install: result = try service.install()
    case .start: result = try service.start()
    case .stop: result = try service.stop()
    case .restart: result = try service.restart()
    case .uninstall: result = try service.uninstall()
    case .status: fatalError("service status is handled above")
    }
    print(serviceMessage(for: result))
    exit(0)
  } catch {
    fail(String(describing: error))
  }
case .listen, .run:
  break
}

let dryRun: Bool
let configurationURL: URL?
let configuration: Configuration?
switch request {
case .listen:
  dryRun = true
  configurationURL = nil
  configuration = nil
case .run(let url, let isDryRun):
  dryRun = isDryRun
  configurationURL = url
  configuration = loadConfiguration(
    at: url, startupDiagnostics: managedStartupDiagnostics)
case .help, .version, .initialize, .check, .service:
  fatalError("Handled CLI request unexpectedly reached device startup")
}

let executionMode: GestureExecutionMode
switch request {
case .listen: executionMode = .listen
case .run(_, let isDryRun): executionMode = isDryRun ? .dryRun : .run
case .help, .version, .initialize, .check, .service:
  fatalError("Handled CLI request unexpectedly reached device startup")
}
let actionPolicy = GestureActionPolicy(mode: executionMode)
let reloadPolicy = ConfigurationReloadPolicy(
  initialConfiguration: configuration, mode: executionMode)
let reloadAdapter: ConfigurationReloadAdapter?
if executionMode == .run, let configurationURL {
  let currentExecutableURL = URL(
    fileURLWithPath: CommandLine.arguments[0], relativeTo: environment.currentDirectory
  ).standardizedFileURL
  let sourceResolver = ConfigurationReloadSourceResolver(
    nixManaged: environment.values[ConfigurationReloadSourceResolver.nixManagedEnvironmentKey]
      == "1",
    fallbackURL: configurationURL,
    currentExecutableURL: currentExecutableURL)
  reloadAdapter = ConfigurationReloadAdapter(sourceResolver: sourceResolver) { configuration in
    try ConfigurationDecision.validateExecutables(in: configuration) {
      FileManager.default.isExecutableFile(atPath: $0)
    }
  }
} else {
  reloadAdapter = nil
}

let lockURL = environment.homeDirectory
  .appendingPathComponent("Library/Application Support/aerospace-gestures", isDirectory: true)
  .appendingPathComponent("listener.lock")
let listenerLock: InstanceLock
do {
  listenerLock = try InstanceLock.acquire(
    at: lockURL,
    under: environment.homeDirectory,
    waitForContention: ProcessInfo.processInfo.environment["AEROSPACE_GESTURES_MANAGED"] == "1")
} catch {
  try? managedStartupDiagnostics?.record(.listenerLockUnavailable)
  fail(String(describing: error))
}

let runner = CommandRunner()
var detectors: [UInt: SwipeDetector] = [:]
var receivedFrame = false

let onFrame: (UInt, UInt32, [Contact]) -> Void = { device, _, contacts in
  let frameToken = actionPolicy.captureFrame(device: device, contactCount: contacts.count)
  DispatchQueue.main.async {
    guard actionPolicy.isCurrent(frameToken) else {
      if contacts.isEmpty { detectors.removeValue(forKey: device) }
      return
    }
    if !receivedFrame {
      receivedFrame = true
      print("Receiving trackpad frames")
      fflush(stdout)
    }
    let activeConfiguration = reloadPolicy.activeConfiguration
    var detector =
      detectors[device]
      ?? SwipeDetector(threshold: activeConfiguration?.threshold ?? 0.15)
    let gesture = detector.update(contacts)
    detectors[device] = detector
    guard let gesture else { return }
    let actionContext =
      dryRun ? " (listen only)" : actionPolicy.state == .paused ? " (actions paused)" : ""
    print("\(gesture.fingers)-finger \(gesture.direction.rawValue)\(actionContext)")
    fflush(stdout)
    guard
      let binding = CommandDecision.binding(
        for: gesture, in: activeConfiguration?.bindings ?? [], dryRun: dryRun),
      actionPolicy.mayDispatch(gesture, from: frameToken)
    else { return }
    if !runner.run(
      binding.command,
      completion: { message in
        print(message)
        fflush(stdout)
      })
    {
      print("Command not started (busy or launch failed)")
      fflush(stdout)
    }
  }
}

if let error = MultitouchInput.start(onFrame: onFrame) {
  let diagnostic = StartupDiagnostic.inputInitializationFailure(for: error)
  try? managedStartupDiagnostics?.record(diagnostic)
  fail(error)
}
try? managedStartupDiagnostics?.clear()
print("Listening. Private API is experimental; system gestures are NOT suppressed. Ctrl-C to stop.")
fflush(stdout)
DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
  if !receivedFrame {
    print(
      "No frames yet. Touch the trackpad. If still silent, check Input Monitoring permissions and restart."
    )
    fflush(stdout)
  }
}
let shutdown = ListenerShutdown(
  stopInput: { MultitouchInput.stop() },
  stopCommands: { completion in runner.stop(completion: completion) })
var signals: [DispatchSourceSignal] = []
for number in [SIGINT, SIGTERM] {
  signal(number, SIG_IGN)
  let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
  source.setEventHandler {
    shutdown.stop { exit(0) }
  }
  source.resume()
  signals.append(source)
}
withExtendedLifetime(listenerLock) {
  if actionPolicy.showsMenuBarControl {
    MainActor.assumeIsolated {
      guard let reloadAdapter else { fatalError("Normal run requires a config reload adapter") }
      runMenuBarApplication(
        actionPolicy: actionPolicy,
        reloadPolicy: reloadPolicy,
        reloadAdapter: reloadAdapter,
        onSuccessfulReload: {
          actionPolicy.invalidateFramesForConfigurationReload()
          detectors.removeAll()
        })
    }
  } else {
    dispatchMain()
  }
}

@MainActor
func runMenuBarApplication(
  actionPolicy: GestureActionPolicy,
  reloadPolicy: ConfigurationReloadPolicy,
  reloadAdapter: ConfigurationReloadAdapter,
  onSuccessfulReload: @escaping () -> Void
) {
  let application = NSApplication.shared
  guard application.setActivationPolicy(.accessory) else {
    fail("Cannot configure the menu-bar action control")
  }
  let menuBarControl = MenuBarControl(
    actionPolicy: actionPolicy,
    reloadPolicy: reloadPolicy,
    reloadAdapter: reloadAdapter,
    onSuccessfulReload: onSuccessfulReload)
  withExtendedLifetime(menuBarControl) {
    application.run()
  }
}

func serviceMessage(for result: ServiceOperationResult) -> String {
  switch result {
  case .installed: return "Installed and started the per-user LaunchAgent."
  case .updated: return "Updated and restarted the per-user LaunchAgent."
  case .alreadyInstalled: return "LaunchAgent is already installed and running."
  case .started: return "Started or activated the per-user LaunchAgent."
  case .alreadyRunning: return "LaunchAgent is already running; no change made."
  case .stopped: return "Stopped the per-user LaunchAgent; login startup remains enabled."
  case .alreadyStopped: return "LaunchAgent is already stopped."
  case .restarted: return "Restarted the per-user LaunchAgent."
  case .uninstalled: return "Uninstalled the per-user LaunchAgent; binary/config were preserved."
  case .notInstalled: return "LaunchAgent is not installed; no change made."
  }
}
