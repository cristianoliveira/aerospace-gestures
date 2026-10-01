import Foundation
import TOMLKit

public enum Direction: String, Codable, Sendable { case left, right, up, down }

public struct Gesture: Equatable, Hashable {
  public let fingers: Int
  public let direction: Direction
  public init(fingers: Int, direction: Direction) {
    self.fingers = fingers
    self.direction = direction
  }
}

public struct Contact {
  public let id: Int
  public let x: Double
  public let y: Double
  public init(id: Int, x: Double, y: Double) {
    self.id = id
    self.x = x
    self.y = y
  }
}

public struct SwipeDetector {
  private let threshold: Double
  private var origin: [Contact] = []
  private var fired = false

  public init(threshold: Double) { self.threshold = threshold }

  public mutating func update(_ contacts: [Contact]) -> Gesture? {
    guard !contacts.isEmpty else {
      origin = []
      fired = false
      return nil
    }
    guard !fired else { return nil }
    guard (3...5).contains(contacts.count),
      contacts.allSatisfy({ $0.x.isFinite && $0.y.isFinite })
    else {
      origin = []
      return nil
    }

    let sorted = contacts.sorted { $0.id < $1.id }
    guard sorted.map(\.id) == origin.map(\.id) else {
      origin = sorted
      return nil
    }

    let deltas = zip(sorted, origin).map { ($0.x - $1.x, $0.y - $1.y) }
    let dx = deltas.map { $0.0 }.reduce(0, +) / Double(sorted.count)
    let dy = deltas.map { $0.1 }.reduce(0, +) / Double(sorted.count)
    let horizontal = abs(dx) > abs(dy) * 1.3
    let vertical = abs(dy) > abs(dx) * 1.3
    guard horizontal || vertical else { return nil }
    let distance = horizontal ? dx : dy
    guard abs(distance) >= threshold else { return nil }
    // All fingers must move together; reject pinch/rotation-like motion.
    guard
      deltas.allSatisfy({ delta in
        let movement = horizontal ? delta.0 : delta.1
        return movement * distance > 0 && abs(movement) >= threshold / 2
      })
    else { return nil }

    fired = true
    let direction: Direction = horizontal ? (dx > 0 ? .right : .left) : (dy > 0 ? .up : .down)
    return Gesture(fingers: sorted.count, direction: direction)
  }
}

public struct Binding: Decodable, Sendable {
  public let fingers: Int
  public let direction: Direction
  public let command: [String]
  public var gesture: Gesture { Gesture(fingers: fingers, direction: direction) }
}

public struct Configuration: Decodable, Sendable {
  public let threshold: Double
  public let bindings: [Binding]

  enum CodingKeys: String, CodingKey { case threshold, bindings }
  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    threshold = try values.decodeIfPresent(Double.self, forKey: .threshold) ?? 0.15
    bindings = try values.decode([Binding].self, forKey: .bindings)
  }

  public static func load(_ data: Data) throws -> Configuration {
    guard let toml = String(data: data, encoding: .utf8) else {
      throw ConfigurationError.invalid("configuration must be valid UTF-8")
    }

    let config: Configuration
    do {
      config = try TOMLDecoder().decode(Configuration.self, from: toml)
    } catch let error as TOMLParseError {
      let position = error.source.begin
      throw ConfigurationError.invalid(
        "invalid TOML at line \(position.line), column \(position.column): \(error.description)")
    }

    guard config.threshold.isFinite, (0.02...0.8).contains(config.threshold) else {
      throw ConfigurationError.invalid("threshold must be between 0.02 and 0.8")
    }
    var seen = Set<Gesture>()
    for binding in config.bindings {
      guard (3...5).contains(binding.fingers) else {
        throw ConfigurationError.invalid("finger count must be 3, 4, or 5")
      }
      guard let executable = binding.command.first, executable.hasPrefix("/"),
        binding.command.allSatisfy({ !$0.contains("\0") })
      else {
        throw ConfigurationError.invalid(
          "command must be an argv array starting with an absolute executable path")
      }
      guard seen.insert(binding.gesture).inserted else {
        throw ConfigurationError.invalid("duplicate gesture binding")
      }
    }
    return config
  }
}

public enum ConfigurationError: Error, CustomStringConvertible {
  case invalid(String)
  public var description: String {
    switch self {
    case .invalid(let message): return message
    }
  }
}
