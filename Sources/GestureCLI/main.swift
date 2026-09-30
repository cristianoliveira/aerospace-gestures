import Darwin
import Foundation
import GestureCLIPolicy
import GestureCore
import GestureInfrastructure
import MultitouchInput

let help = """
  Usage:
    aerospace-gestures listen
    aerospace-gestures check <config.json>
    aerospace-gestures run <config.json> [--dry-run]

  Examples:
    swift run aerospace-gestures listen
    swift run aerospace-gestures check config.example.json
    swift run aerospace-gestures run config.example.json --dry-run
    swift run aerospace-gestures run config.example.json

  Recognizes 3–5 finger swipes globally using a private macOS API.
  listen and --dry-run never execute commands. Ctrl-C stops the listener.
  Requires a multitouch trackpad and macOS 13+. Disable conflicting gestures
  in System Settings > Trackpad > More Gestures. This tool does not suppress them.
  Use absolute executable paths in config; discover AeroSpace with: command -v aerospace
  If no gestures appear, check System Settings > Privacy & Security > Input Monitoring
  for your terminal, then restart the listener. Do not run with sudo.
  """

func log(_ message: String) {
  print(message)
  fflush(stdout)
}

func fail(_ message: String) -> Never {
  FileHandle.standardError.write(
    Data("Error: \(message)\nRun aerospace-gestures --help for usage.\n".utf8))
  exit(1)
}

let args = Array(CommandLine.arguments.dropFirst())
if args.isEmpty || args == ["--help"] || args == ["-h"] {
  print(help)
  exit(0)
}
let mode = args[0]
var configuration: Configuration?
let dryRun: Bool
switch mode {
case "listen":
  guard args.count == 1 else { fail("listen takes no arguments") }
  dryRun = true
case "run", "check":
  guard args.count == 2 || (mode == "run" && args.count == 3 && args[2] == "--dry-run") else {
    fail("Expected \(mode) <config.json>\(mode == "run" ? " [--dry-run]" : "")")
  }
  do {
    configuration = try Configuration.load(Data(contentsOf: URL(fileURLWithPath: args[1])))
    for binding in configuration!.bindings {
      guard FileManager.default.isExecutableFile(atPath: binding.command[0]) else {
        fail("Not executable: \(binding.command[0]). Update the config using command -v <program>.")
      }
    }
  } catch { fail("Cannot load configuration: \(error)") }
  if mode == "check" {
    log("Configuration valid: \(configuration!.bindings.count) bindings")
    exit(0)
  }
  dryRun = args.count == 3
default:
  fail("Unknown command: \(mode)")
}

let runner = CommandRunner()
var detectors: [UInt: SwipeDetector] = [:]
var receivedFrame = false

let onFrame: (UInt, [Contact]) -> Void = { device, contacts in
  DispatchQueue.main.async {
    if !receivedFrame {
      receivedFrame = true
      log("Receiving trackpad frames")
    }
    var detector = detectors[device] ?? SwipeDetector(threshold: configuration?.threshold ?? 0.15)
    let gesture = detector.update(contacts)
    detectors[device] = detector
    guard let gesture else { return }
    log("\(gesture.fingers)-finger \(gesture.direction.rawValue)\(dryRun ? " (listen only)" : "")")
    guard
      let binding = CommandDecision.binding(
        for: gesture, in: configuration?.bindings ?? [], dryRun: dryRun)
    else { return }
    if !runner.run(binding.command, completion: log) {
      log("Command not started (busy or launch failed)")
    }
  }
}

if let error = MultitouchInput.start(onFrame: onFrame) { fail(error) }
log("Listening. Private API is experimental; system gestures are NOT suppressed. Ctrl-C to stop.")
DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
  if !receivedFrame {
    log(
      "No frames yet. Touch the trackpad. If still silent, check Input Monitoring permissions and restart."
    )
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
