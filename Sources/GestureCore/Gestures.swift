import Foundation
import TOMLKit

public enum Direction: String, Codable, Sendable { case left, right, up, down }

public struct Gesture: Equatable, Hashable, Sendable {
  public enum Kind: Sendable { case swipe, pinchIn, pinchOut }

  public let kind: Kind
  public let fingers: Int
  public let direction: Direction?

  public init(fingers: Int, direction: Direction) {
    self.kind = .swipe
    self.fingers = fingers
    self.direction = direction
  }

  private init(kind: Kind) {
    self.kind = kind
    self.fingers = 2
    self.direction = nil
  }

  public static let pinchIn = Gesture(kind: .pinchIn)
  public static let pinchOut = Gesture(kind: .pinchOut)

  public var displayName: String {
    switch kind {
    case .swipe:
      return "\(fingers)-finger \(direction?.rawValue ?? "unknown direction")"
    case .pinchIn:
      return "two-finger pinch in"
    case .pinchOut:
      return "two-finger pinch out"
    }
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

/// Deterministic per-contact-sequence recognition for swipes and two-finger pinches.
public struct GestureDetector {
  private static let minimumPinchSeparation = 0.04
  private let swipeThreshold: Double
  private let pinchThreshold: Double
  private var origin: [Contact] = []
  private var fired = false

  public init(threshold: Double, pinchThreshold: Double = 0.2) {
    self.swipeThreshold = threshold
    self.pinchThreshold = pinchThreshold
  }

  public mutating func update(_ contacts: [Contact]) -> Gesture? {
    guard !contacts.isEmpty else {
      origin = []
      fired = false
      return nil
    }
    guard !fired else { return nil }
    guard (2...5).contains(contacts.count),
      contacts.allSatisfy({ $0.x.isFinite && $0.y.isFinite })
    else {
      origin = []
      return nil
    }

    let sorted = contacts.sorted { $0.id < $1.id }
    guard Set(sorted.map(\.id)).count == sorted.count else {
      origin = []
      return nil
    }
    guard sorted.map(\.id) == origin.map(\.id) else {
      origin = sorted
      return nil
    }

    if sorted.count == 2 {
      return detectPinch(sorted)
    }
    return detectSwipe(sorted)
  }

  private mutating func detectPinch(_ contacts: [Contact]) -> Gesture? {
    let firstOrigin = origin[0]
    let secondOrigin = origin[1]
    let axisX = secondOrigin.x - firstOrigin.x
    let axisY = secondOrigin.y - firstOrigin.y
    let baseline = hypot(axisX, axisY)
    guard baseline.isFinite, baseline >= Self.minimumPinchSeparation else { return nil }

    let currentX = contacts[1].x - contacts[0].x
    let currentY = contacts[1].y - contacts[0].y
    let currentSeparation = hypot(currentX, currentY)
    guard currentSeparation.isFinite else { return nil }

    let relativeChange = (baseline - currentSeparation) / baseline
    guard abs(relativeChange) >= pinchThreshold else { return nil }

    let unitX = axisX / baseline
    let unitY = axisY / baseline
    let firstProjection =
      (contacts[0].x - firstOrigin.x) * unitX + (contacts[0].y - firstOrigin.y) * unitY
    let secondProjection =
      (contacts[1].x - secondOrigin.x) * unitX + (contacts[1].y - secondOrigin.y) * unitY
    let minimumRadialMovement = baseline * pinchThreshold * 0.1

    if relativeChange > 0,
      firstProjection >= minimumRadialMovement,
      secondProjection <= -minimumRadialMovement
    {
      fired = true
      return .pinchIn
    }
    if relativeChange < 0,
      firstProjection <= -minimumRadialMovement,
      secondProjection >= minimumRadialMovement
    {
      fired = true
      return .pinchOut
    }
    return nil
  }

  private mutating func detectSwipe(_ contacts: [Contact]) -> Gesture? {
    let deltas = zip(contacts, origin).map { ($0.x - $1.x, $0.y - $1.y) }
    let dx = deltas.map { $0.0 }.reduce(0, +) / Double(contacts.count)
    let dy = deltas.map { $0.1 }.reduce(0, +) / Double(contacts.count)
    let horizontal = abs(dx) > abs(dy) * 1.3
    let vertical = abs(dy) > abs(dx) * 1.3
    guard horizontal || vertical else { return nil }
    let distance = horizontal ? dx : dy
    guard abs(distance) >= swipeThreshold else { return nil }
    // All fingers must move together; reject pinch/rotation-like motion.
    guard
      deltas.allSatisfy({ delta in
        let movement = horizontal ? delta.0 : delta.1
        return movement * distance > 0 && abs(movement) >= swipeThreshold / 2
      })
    else { return nil }

    fired = true
    let direction: Direction = horizontal ? (dx > 0 ? .right : .left) : (dy > 0 ? .up : .down)
    return Gesture(fingers: contacts.count, direction: direction)
  }
}

public struct Binding: Decodable, Sendable {
  public let gesture: Gesture
  public let command: [String]

  enum CodingKeys: String, CodingKey { case fingers, direction, gesture, command }

  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    let configuredGesture = try values.decodeIfPresent(String.self, forKey: .gesture)
    let fingers = try values.decodeIfPresent(Int.self, forKey: .fingers)
    let direction = try values.decodeIfPresent(Direction.self, forKey: .direction)
    command = try values.decode([String].self, forKey: .command)

    if let configuredGesture {
      guard fingers == nil, direction == nil else {
        throw ConfigurationError.invalid(
          "gesture bindings cannot also specify fingers or direction")
      }
      switch configuredGesture {
      case "pinch_in": gesture = .pinchIn
      case "pinch_out": gesture = .pinchOut
      default:
        throw ConfigurationError.invalid(
          "gesture must be 'pinch_in' or 'pinch_out'")
      }
    } else {
      guard let fingers, let direction else {
        throw ConfigurationError.invalid(
          "swipe bindings must specify both fingers and direction; pinch bindings use gesture")
      }
      gesture = Gesture(fingers: fingers, direction: direction)
    }
  }
}

public struct Configuration: Decodable, Sendable {
  public let threshold: Double
  public let pinchThreshold: Double
  public let bindings: [Binding]
  public let debugCommandOutput: Bool

  enum CodingKeys: String, CodingKey {
    case threshold, bindings
    case pinchThreshold = "pinch_threshold"
    case debugCommandOutput = "debug_command_output"
  }
  public init(from decoder: Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    threshold = try values.decodeIfPresent(Double.self, forKey: .threshold) ?? 0.15
    pinchThreshold = try values.decodeIfPresent(Double.self, forKey: .pinchThreshold) ?? 0.2
    bindings = try values.decode([Binding].self, forKey: .bindings)
    debugCommandOutput = try values.decodeIfPresent(Bool.self, forKey: .debugCommandOutput) ?? false
  }

  public static func load(_ data: Data) throws -> Configuration {
    guard let toml = String(data: data, encoding: .utf8) else {
      throw ConfigurationError.invalid("configuration must be valid UTF-8")
    }

    let config: Configuration
    do {
      config = try TOMLDecoder().decode(Configuration.self, from: toml)
    } catch let error as ConfigurationError {
      throw error
    } catch let error as TOMLParseError {
      let position = error.source.begin
      throw ConfigurationError.invalid(
        "invalid TOML at line \(position.line), column \(position.column): \(error.description)")
    }

    guard config.threshold.isFinite, (0.02...0.8).contains(config.threshold) else {
      throw ConfigurationError.invalid("threshold must be between 0.02 and 0.8")
    }
    guard config.pinchThreshold.isFinite, (0.05...0.5).contains(config.pinchThreshold) else {
      throw ConfigurationError.invalid("pinch_threshold must be between 0.05 and 0.5")
    }
    var seen = Set<Gesture>()
    for binding in config.bindings {
      if binding.gesture.kind == .swipe {
        guard (3...5).contains(binding.gesture.fingers) else {
          throw ConfigurationError.invalid("finger count must be 3, 4, or 5")
        }
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
