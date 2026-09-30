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

func loadConfiguration(at url: URL) -> Configuration {
  do {
    let configuration = try ConfigurationFile.load(at: url)
    try ConfigurationDecision.validateExecutables(in: configuration) {
      FileManager.default.isExecutableFile(atPath: $0)
    }
    return configuration
  } catch let error as ConfigurationFileError {
    if case .cannotRead = error, !FileManager.default.fileExists(atPath: url.path) {
      fail(CLIConfigurationFailure.missing(at: url))
    }
    fail("\(error)")
  } catch {
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

switch request {
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
case .listen:
  break
case .run:
  break
}

let dryRun: Bool
let configuration: Configuration?
switch request {
case .listen:
  dryRun = true
  configuration = nil
case .run(let configurationURL, let isDryRun):
  dryRun = isDryRun
  configuration = loadConfiguration(at: configurationURL)
case .help, .initialize, .check:
  fatalError("Handled CLI request unexpectedly reached device startup")
}

let runner = CommandRunner()
var detectors: [UInt: SwipeDetector] = [:]
var receivedFrame = false

let onFrame: (UInt, [Contact]) -> Void = { device, contacts in
  DispatchQueue.main.async {
    if !receivedFrame {
      receivedFrame = true
      print("Receiving trackpad frames")
      fflush(stdout)
    }
    var detector = detectors[device] ?? SwipeDetector(threshold: configuration?.threshold ?? 0.15)
    let gesture = detector.update(contacts)
    detectors[device] = detector
    guard let gesture else { return }
    print(
      "\(gesture.fingers)-finger \(gesture.direction.rawValue)\(dryRun ? " (listen only)" : "")")
    fflush(stdout)
    guard
      let binding = CommandDecision.binding(
        for: gesture, in: configuration?.bindings ?? [], dryRun: dryRun)
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

if let error = MultitouchInput.start(onFrame: onFrame) { fail(error) }
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
var signals: [DispatchSourceSignal] = []
for number in [SIGINT, SIGTERM] {
  signal(number, SIG_IGN)
  let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
  source.setEventHandler {
    MultitouchInput.stop()
    runner.stop()
    exit(0)
  }
  source.resume()
  signals.append(source)
}
dispatchMain()
