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
  case help
  case version

  /// Maps every advertised command to a navigable `help <command>` topic.
  public init(named name: String) throws {
    switch name {
    case "init": self = .initialize
    case "check": self = .check
    case "run": self = .run
    case "listen": self = .listen
    case "service": self = .service
    case "help": self = .help
    case "version": self = .version
    default:
      throw CLIArgumentError.invalidArguments(
        "Unknown help topic: \(name)", topic: .help)
    }
  }
}

public enum CLIHelp {
  public static func text(for topic: CLIHelpTopic, defaultConfigurationURL: URL) -> String {
    let command = "aerospace-gestures"
    let name = """
      Name:
        \(command) v\(CLIVersion.current) — map macOS trackpad swipes to commands
      """
    let usage: String
    let flags: String
    let description: String
    let commandDetails: String?
    let example: String
    switch topic {
    case .root:
      usage = """
        Usage:
          \(command) <command> [options]
        """
      flags = """
        Flags:
          --help, -h   Show help for a command
          --version    Print the binary version
          --dry-run    run only: observe gestures without executing commands
        """
      commandDetails = """
        Available Commands:
          init      Create the popup example configuration; never overwrites
          listen    Observe gestures without executing commands
          check     Validate configuration and executable paths
          run       Run with menu-bar pause and configuration reload
          service   Manage the per-user GUI LaunchAgent
          help      Show help for a command
          version   Print the binary version
        """
      description = """
        init creates a safe three-finger-down popup config and never overwrites a file or symlink.
        check validates configuration and executable paths without starting devices or commands.
        service manages this user's GUI LaunchAgent; it never grants permissions or builds the binary.
        """
      example = "\(command) init && \(command) check && \(command) run --dry-run"
    case .initialize:
      usage = "Usage: \(command) init [config.toml]"
      flags = """
        Flags:
          --help, -h   Show this help
        """
      commandDetails = nil
      description =
        "Creates the popup example exclusively. Existing files and symlinks are preserved."
      example = "\(command) init"
    case .listen:
      usage = "Usage: \(command) listen"
      flags = """
        Flags:
          --help, -h   Show this help
        """
      commandDetails = nil
      description =
        "Observes gestures without executing commands or showing an action toggle; requires macOS 13+ and a multitouch trackpad."
      example = "\(command) listen"
    case .check:
      usage = "Usage: \(command) check [config.toml]"
      flags = """
        Flags:
          --help, -h   Show this help
        """
      commandDetails = nil
      description = "Validates TOML and executable paths without starting devices or commands."
      example = "\(command) check /path/to/config.toml"
    case .run:
      usage = "Usage: \(command) run [config.toml] [--dry-run]"
      flags = """
        Flags:
          --help, -h    Show this help
          --dry-run     Observe gestures without executing commands
        """
      commandDetails = nil
      description =
        "Normal run starts enabled with a menu-bar action toggle and Reload configuration; pausing keeps listening but blocks new commands. Reload validates before swapping without restarting input. --dry-run observes only and never enables command execution."
      example = "\(command) run --dry-run"
    case .service:
      usage = "Usage: \(command) service <install|status|start|stop|restart|uninstall>"
      flags = """
        Flags:
          --help, -h   Show this help
        """
      commandDetails = """
        Actions:
          install     Capture the config path, install and start the LaunchAgent
          status      Report plist ownership, launchd state, and startup diagnostics
          start       Load and start the installed service
          stop        Unload for this login; retains the plist
          restart     Validate the captured config, then reload the service
          uninstall   Remove only the managed plist; preserves binary/config
        """
      description = """
        Manages the per-user GUI LaunchAgent at ~/Library/LaunchAgents/com.aerospace-gestures.plist.
        install requires a prebuilt executable at ~/.local/bin/aerospace-gestures and a valid config.
        install never builds software or changes Input Monitoring/TCC permissions.
        stop retains the plist; uninstall removes only the owned plist and preserves binary/config.
        Persistent logs are disabled; launchd stdout/stderr are /dev/null (zero retained bytes).
        status reports launchd registration/process state, not trackpad responsiveness.
        """
      example = "\(command) service status"
    case .help:
      usage = "Usage: \(command) help [command]"
      flags = """
        Flags:
          --help, -h   Show this help
        """
      commandDetails = nil
      description = "Shows root help or focused help for an advertised command."
      example = "\(command) help service"
    case .version:
      usage = "Usage: \(command) version"
      flags = """
        Flags:
          --help, -h   Show this help
        """
      commandDetails = nil
      description = "Prints the binary version and exits without starting devices or services."
      example = "\(command) --version"
    }

    var sections = [name, usage]
    if let commandDetails { sections.append(commandDetails) }
    sections.append(flags)
    sections.append(description)
    sections.append("""
      Default configuration: \(defaultConfigurationURL.path)
      Prerequisites: macOS 13+ and a multitouch trackpad for listen/run; init/check need no device. Swift 5.9+ to build.
      If the default file is missing, create it with `\(command) init`.
      To validate a file: `\(command) check <config.toml>`.
      If init reports that a file exists, inspect it with check or choose another path with `\(command) init <config.toml>`.
      """)
    sections.append("""
      Examples:
        \(example)
      """)
    sections.append(
      "Private MultitouchSupport API is experimental and system gestures are not suppressed.")
    return sections.joined(separator: "\n\n")
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
  case version
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
    if arguments == ["--version"] { return .version }

    if command == "help" {
      guard arguments.count <= 2 else {
        throw usageError("Expected help [command]", topic: .help)
      }
      guard arguments.count == 2 else { return .help(.root) }
      if arguments[1] == "--help" || arguments[1] == "-h" { return .help(.help) }
      return .help(try CLIHelpTopic(named: arguments[1]))
    }

    let options = Array(arguments.dropFirst())
    if command == "version" {
      let (flags, positionals) = try parseOptions(options, for: command, topic: .version)
      if flags.contains("--help") || flags.contains("-h") { return .help(.version) }
      guard positionals.isEmpty else {
        throw usageError("version takes no arguments", topic: .version)
      }
      return .version
    }

    switch command {
    case "listen":
      let (flags, positionals) = try parseOptions(options, for: command, topic: .listen)
      if flags.contains("--help") || flags.contains("-h") { return .help(.listen) }
      guard positionals.isEmpty, flags.isEmpty else {
        throw usageError("listen takes no arguments", topic: .listen)
      }
      return .listen
    case "init", "check":
      let topic = command == "init" ? CLIHelpTopic.initialize : .check
      let (flags, positionals) = try parseOptions(options, for: command, topic: topic)
      if flags.contains("--help") || flags.contains("-h") { return .help(topic) }
      guard positionals.count <= 1 else {
        throw usageError("Expected \(command) [config.toml]", topic: topic)
      }
      let configuration = ConfigurationPath.resolve(
        explicitPath: positionals.first, in: environment)
      return command == "init" ? .initialize(configuration: configuration) : .check(
        configuration: configuration)
    case "run":
      let (flags, positionals) = try parseOptions(
        options, for: command, topic: .run, extraAllowed: ["--dry-run"])
      if flags.contains("--help") || flags.contains("-h") { return .help(.run) }
      guard positionals.count <= 1 else {
        throw usageError("Expected run [config.toml] [--dry-run]", topic: .run)
      }
      return .run(
        configuration: ConfigurationPath.resolve(explicitPath: positionals.first, in: environment),
        dryRun: flags.contains("--dry-run"))
    case "service":
      if options.contains("--help") || options.contains("-h") { return .help(.service) }
      if let stray = options.first(where: { $0.hasPrefix("-") }) {
        throw usageError("Unknown option '\(stray)' for service", topic: .service)
      }
      guard options.count == 1, let action = CLIServiceAction(rawValue: options[0]) else {
        throw usageError(
          "Expected service install|status|start|stop|restart|uninstall",
          topic: .service)
      }
      return .service(action)
    default:
      throw CLIArgumentError.unknownCommand(command)
    }
  }

  /// Splits options into flags and positionals so a dash-prefixed token is never
  /// mistaken for a config path. Unrecognized options fail closed with focused help.
  private static func parseOptions(
    _ options: [String], for command: String, topic: CLIHelpTopic,
    extraAllowed: Set<String> = []
  ) throws -> (flags: Set<String>, positionals: [String]) {
    let allowed = Set(["--help", "-h"]).union(extraAllowed)
    var flags = Set<String>()
    var positionals: [String] = []
    for option in options {
      guard option.hasPrefix("-") else {
        positionals.append(option)
        continue
      }
      guard allowed.contains(option) else {
        throw usageError("Unknown option '\(option)' for \(command)", topic: topic)
      }
      flags.insert(option)
    }
    return (flags, positionals)
  }

  private static func usageError(
    _ message: String, topic: CLIHelpTopic
  ) -> CLIArgumentError {
    .invalidArguments(message, topic: topic)
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
      .appendingPathComponent("config.toml")
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
  case invalidArguments(String, topic: CLIHelpTopic)

  public var topic: CLIHelpTopic {
    switch self {
    case .unknownCommand: return .root
    case .invalidArguments(_, let topic): return topic
    }
  }

  public var description: String {
    switch self {
    case .unknownCommand(let command): return "Unknown command: \(command)"
    case .invalidArguments(let message, _): return message
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
