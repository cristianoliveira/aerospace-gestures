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
        \(command) v\(CLIVersion.current) — map macOS trackpad gestures to commands
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
          -h, --help      Show help for a command
          -v, --version   Print the binary version
          --dry-run       run only: observe gestures without executing commands
        """
      commandDetails = """
        Available Commands:
          init      Create the popup example configuration; never overwrites
          listen    Observe gestures; try `listen --help` for actions
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
      example =
        "\(command) init ./config.toml && \(command) check ./config.toml && \(command) run ./config.toml --dry-run"
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
      usage = "Usage: \(command) listen <start>"
      flags = """
        Flags:
          --help, -h   Show this help
        """
      commandDetails = """
        Actions:
          start   Observe gestures without executing commands
        """
      description =
        "listen start observes gestures without executing commands or showing an action toggle; requires macOS 13+ and a multitouch trackpad."
      example = "\(command) listen start"
    case .check:
      usage = "Usage: \(command) check <config.toml>"
      flags = """
        Flags:
          --help, -h   Show this help
        """
      commandDetails = nil
      description = "Validates TOML and executable paths without starting devices or commands."
      example = "\(command) check /path/to/config.toml"
    case .run:
      usage = "Usage: \(command) run <config.toml> [--dry-run]"
      flags = """
        Flags:
          --help, -h    Show this help
          --dry-run     Observe gestures without executing commands
        """
      commandDetails = nil
      description =
        "Normal run starts enabled with a menu-bar action toggle and Reload configuration; pausing keeps listening but blocks new commands. Reload validates before swapping without restarting input. --dry-run observes only and never enables command execution."
      example = "\(command) run /path/to/config.toml --dry-run"
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
    sections.append(
      """
      Default configuration path for init and service: \(defaultConfigurationURL.path)
      Prerequisites: macOS 13+ and a multitouch trackpad for listen/run; init/check need no device. Swift 5.9+ to build.
      If the default file is missing, create it with `\(command) init`.
      To validate a file: `\(command) check <config.toml>`.
      If init reports that a file exists, inspect it with check or choose another path with `\(command) init <config.toml>`.
      """)
    sections.append(
      """
      Examples:
        \(example)
      """)
    sections.append(
      "Bindings use fingers and direction: 2–5 with 'in'/'out', or 3–5 with 'left'/'right'/'up'/'down'. Pinch and swipe bindings may coexist at one finger count; pinch_threshold is independent from the swipe threshold. The obsolete gesture field is rejected."
    )
    sections.append(
      "Private MultitouchSupport API is experimental and system gestures are not suppressed. Pinch bindings do not suppress macOS pinch-to-zoom; real-trackpad delivery and interaction require manual validation."
    )
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

  private struct CommandContract {
    let topic: CLIHelpTopic
    let operandCount: ClosedRange<Int>
    let operandSynopsis: String
    let extraAllowedOptions: Set<String>
    let makeRequest: ([String], Set<String>, CLIEnvironment) throws -> CLIRequest

    init(
      topic: CLIHelpTopic,
      operandCount: ClosedRange<Int>,
      operandSynopsis: String = "",
      extraAllowedOptions: Set<String> = [],
      makeRequest: @escaping ([String], Set<String>, CLIEnvironment) throws -> CLIRequest
    ) {
      self.topic = topic
      self.operandCount = operandCount
      self.operandSynopsis = operandSynopsis
      self.extraAllowedOptions = extraAllowedOptions
      self.makeRequest = makeRequest
    }

    func validate(_ operands: [String], command: String) throws {
      guard operandCount.contains(operands.count) else {
        let expected = operandSynopsis.isEmpty ? command : "\(command) \(operandSynopsis)"
        throw CLIArgumentError.invalidArguments("Expected \(expected)", topic: topic)
      }
    }
  }

  /// Every named command enters the same option, help, and operand-validation pipeline.
  private static let commandContracts: [String: CommandContract] = [
    "init": CommandContract(
      topic: .initialize, operandCount: 0...1, operandSynopsis: "[config.toml]"
    ) { operands, _, environment in
      .initialize(
        configuration: ConfigurationPath.resolve(
          explicitPath: operands.first, in: environment))
    },
    "check": CommandContract(
      topic: .check, operandCount: 1...1, operandSynopsis: "<config.toml>"
    ) { operands, _, environment in
      .check(
        configuration: ConfigurationPath.resolve(explicitPath: operands[0], in: environment))
    },
    "run": CommandContract(
      topic: .run, operandCount: 1...1, operandSynopsis: "<config.toml>",
      extraAllowedOptions: ["--dry-run"]
    ) { operands, options, environment in
      .run(
        configuration: ConfigurationPath.resolve(explicitPath: operands[0], in: environment),
        dryRun: options.contains("--dry-run"))
    },
    "listen": CommandContract(
      topic: .listen, operandCount: 1...1, operandSynopsis: "<start>"
    ) { operands, _, _ in
      guard operands[0] == "start" else {
        throw CLIArgumentError.invalidArguments("Expected listen start", topic: .listen)
      }
      return .listen
    },
    "service": CommandContract(
      topic: .service, operandCount: 1...1,
      operandSynopsis: "<install|status|start|stop|restart|uninstall>"
    ) { operands, _, _ in
      guard let action = CLIServiceAction(rawValue: operands[0]) else {
        throw CLIArgumentError.invalidArguments(
          "Expected service install|status|start|stop|restart|uninstall", topic: .service)
      }
      return .service(action)
    },
    "help": CommandContract(topic: .help, operandCount: 0...1, operandSynopsis: "[command]") {
      operands, _, _ in
      guard let name = operands.first else { return .help(.root) }
      return .help(try CLIHelpTopic(named: name))
    },
    "version": CommandContract(topic: .version, operandCount: 0...0) { _, _, _ in .version },
  ]

  public static func parse(_ arguments: [String], in environment: CLIEnvironment) throws
    -> CLIRequest
  {
    guard let command = arguments.first else { return .help(.root) }
    if arguments == ["--help"] || arguments == ["-h"] { return .help(.root) }
    if arguments == ["--version"] || arguments == ["-v"] { return .version }
    guard let contract = commandContracts[command] else {
      throw CLIArgumentError.unknownCommand(command)
    }

    let (options, operands) = try parseOptions(
      Array(arguments.dropFirst()), for: command, topic: contract.topic,
      extraAllowed: contract.extraAllowedOptions)
    if options.contains("--help") || options.contains("-h") {
      return .help(contract.topic)
    }
    try contract.validate(operands, command: command)
    return try contract.makeRequest(operands, options, environment)
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
