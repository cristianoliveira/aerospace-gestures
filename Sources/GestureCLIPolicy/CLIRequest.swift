import Foundation
import GestureCore

public struct CLIEnvironment {
  public let values: [String: String]
  public let homeDirectory: URL
  public let currentDirectory: URL

  public init(values: [String: String], homeDirectory: URL, currentDirectory: URL) {
    self.values = values
    self.homeDirectory = homeDirectory
    self.currentDirectory = currentDirectory
  }
}

public enum CLIHelpTopic: Equatable {
  case root
  case initialize
  case check
  case run
  case listen
  case service
}

public enum CLIHelp {
  public static func text(for topic: CLIHelpTopic, defaultConfigurationURL: URL) -> String {
    let command = "aerospace-gestures"
    let usage: String
    let example: String
    let description: String
    switch topic {
    case .root:
      usage = """
        Usage:
          \(command) init [config.json]
          \(command) listen
          \(command) check [config.json]
          \(command) run [config.json] [--dry-run]
          \(command) service <install|status|start|stop|restart|uninstall>
        """
      example = "\(command) init && \(command) check && \(command) run --dry-run"
      description = """
        init creates a safe three-finger-down popup config and never overwrites a file or symlink.
        check validates configuration and executable paths without starting devices or commands.
        service manages this user's GUI LaunchAgent; it never grants permissions or builds the binary.
        """
    case .initialize:
      usage = "Usage: \(command) init [config.json]"
      example = "\(command) init"
      description =
        "Creates the popup example exclusively. Existing files and symlinks are preserved."
    case .listen:
      usage = "Usage: \(command) listen"
      example = "\(command) listen"
      description =
        "Observes gestures without executing commands or showing an action toggle; requires macOS 13+ and a multitouch trackpad."
    case .check:
      usage = "Usage: \(command) check [config.json]"
      example = "\(command) check /path/to/config.json"
      description = "Validates JSON and executable paths without starting devices or commands."
    case .run:
      usage = "Usage: \(command) run [config.json] [--dry-run]"
      example = "\(command) run --dry-run"
      description =
        "Normal run starts enabled with a menu-bar action toggle; pausing keeps listening but blocks new commands. --dry-run observes only and never enables command execution."
    case .service:
      usage = "Usage: \(command) service <install|status|start|stop|restart|uninstall>"
      example = "\(command) service status"
      description = """
        Manages the per-user GUI LaunchAgent at ~/Library/LaunchAgents/com.aerospace-gestures.plist.
        install requires a prebuilt executable at ~/.local/bin/aerospace-gestures and a valid config.
        install never builds software or changes Input Monitoring/TCC permissions.
        stop retains the plist; uninstall removes only the owned plist and preserves binary/config.
        Persistent logs are disabled; launchd stdout/stderr are /dev/null (zero retained bytes).
        status reports launchd registration/process state, not trackpad responsiveness.
        """
    }

    return """
      \(usage)

      Default configuration: \(defaultConfigurationURL.path)
      \(description)
      Prerequisites: macOS 13+ and a multitouch trackpad for listen/run; init/check need no device. Swift 5.9+ to build.
      If the default file is missing, create it with `\(command) init`.
      To validate a file: `\(command) check <config.json>`.
      If init reports that a file exists, inspect it with check or choose another path with `\(command) init <config.json>`.
      Example: `\(example)`
      Private MultitouchSupport API is experimental and system gestures are not suppressed.
      """
  }
}

public enum CLIServiceAction: String, Equatable {
  case install
  case status
  case start
  case stop
  case restart
  case uninstall
}

public enum CLIRequest: Equatable {
  case help(CLIHelpTopic)
  case listen
  case initialize(configuration: URL)
  case check(configuration: URL)
  case run(configuration: URL, dryRun: Bool)
  case service(CLIServiceAction)

  public static func parse(_ arguments: [String], in environment: CLIEnvironment) throws
    -> CLIRequest
  {
    guard let command = arguments.first else { return .help(.root) }
    if arguments == ["--help"] || arguments == ["-h"] { return .help(.root) }

    let options = Array(arguments.dropFirst())
    if options == ["--help"] || options == ["-h"] {
      switch command {
      case "init": return .help(.initialize)
      case "check": return .help(.check)
      case "run": return .help(.run)
      case "listen": return .help(.listen)
      case "service": return .help(.service)
      default: throw CLIArgumentError.unknownCommand(command)
      }
    }

    switch command {
    case "listen":
      guard options.isEmpty else {
        throw CLIArgumentError.invalidArguments("listen takes no arguments")
      }
      return .listen
    case "init":
      guard options.count <= 1 else {
        throw CLIArgumentError.invalidArguments("Expected init [config.json]")
      }
      return .initialize(
        configuration: ConfigurationPath.resolve(
          explicitPath: options.first, in: environment))
    case "check":
      guard options.count <= 1 else {
        throw CLIArgumentError.invalidArguments("Expected check [config.json]")
      }
      return .check(
        configuration: ConfigurationPath.resolve(
          explicitPath: options.first, in: environment))
    case "run":
      var paths = options
      let dryRun = paths.last == "--dry-run"
      if dryRun { paths.removeLast() }
      guard paths.count <= 1 else {
        throw CLIArgumentError.invalidArguments("Expected run [config.json] [--dry-run]")
      }
      return .run(
        configuration: ConfigurationPath.resolve(explicitPath: paths.first, in: environment),
        dryRun: dryRun)
    case "service":
      guard options.count == 1, let action = CLIServiceAction(rawValue: options[0]) else {
        throw CLIArgumentError.invalidArguments(
          "Expected service install|status|start|stop|restart|uninstall")
      }
      return .service(action)
    default:
      throw CLIArgumentError.unknownCommand(command)
    }
  }
}

public enum ConfigurationPath {
  public static func resolve(explicitPath: String?, in environment: CLIEnvironment) -> URL {
    if let explicitPath {
      return URL(fileURLWithPath: explicitPath, relativeTo: environment.currentDirectory)
        .standardizedFileURL
    }

    let configRoot: URL
    if let xdgConfigHome = environment.values["XDG_CONFIG_HOME"],
      !xdgConfigHome.isEmpty, (xdgConfigHome as NSString).isAbsolutePath
    {
      configRoot = URL(fileURLWithPath: xdgConfigHome, isDirectory: true)
    } else {
      configRoot = environment.homeDirectory.appendingPathComponent(".config", isDirectory: true)
    }
    return
      configRoot
      .appendingPathComponent("aerospace-gestures", isDirectory: true)
      .appendingPathComponent("config.json")
      .standardizedFileURL
  }
}

public enum CLIConfigurationFailure {
  public static func missing(at url: URL) -> String {
    "Cannot load configuration at \(url.path): file does not exist. Create the default with `aerospace-gestures init` or create this path with `aerospace-gestures init \(shellQuoted(url.path))`."
  }

  public static func invalid(at url: URL, reason: Error) -> String {
    "Invalid configuration at \(url.path): \(reason)"
  }

  private static func shellQuoted(_ path: String) -> String {
    "'\(path.replacingOccurrences(of: "'", with: "'\\''"))'"
  }
}

public enum ConfigurationDecision {
  public static func validateExecutables(
    in configuration: Configuration, isExecutable: (String) -> Bool
  ) throws {
    for binding in configuration.bindings where !isExecutable(binding.command[0]) {
      throw ConfigurationDecisionError.notExecutable(binding.command[0])
    }
  }
}

public enum CLIArgumentError: Error, CustomStringConvertible {
  case unknownCommand(String)
  case invalidArguments(String)

  public var description: String {
    switch self {
    case .unknownCommand(let command): return "Unknown command: \(command)"
    case .invalidArguments(let message): return message
    }
  }
}

public enum ConfigurationDecisionError: Error, CustomStringConvertible {
  case notExecutable(String)

  public var description: String {
    switch self {
    case .notExecutable(let path):
      return "Not executable: \(path). Update the config using command -v <program>."
    }
  }
}
