import Foundation
import XCTest

@testable import GestureInfrastructure

final class InputDiagnosticsLogTests: XCTestCase {
  func testEmitsOnlyDiagnosticLineToPrivateBoundedFileAndStdout() throws {
    let home = try temporaryHome()
    defer { try? FileManager.default.removeItem(at: home) }
    var stdout: [String] = []
    var stderr: [String] = []
    let log = InputDiagnosticsLog(
      homeDirectory: home,
      maximumBytes: 128,
      writeToStdout: { stdout.append($0) },
      writeToStderr: { stderr.append($0) })
    let line =
      "timestamp_utc=2026-10-15T12:00:00Z input-diagnostics snapshot_successes=2 accepted_frames=8"

    log.emit(line)

    XCTAssertEqual(
      log.fileURL.path,
      home.appendingPathComponent("Library/Logs/aerospace-gestures/input-diagnostics.log").path)
    XCTAssertEqual(try String(contentsOf: log.fileURL, encoding: .utf8), "\(line)\n")
    XCTAssertEqual(stdout, ["\(line)\n"])
    XCTAssertTrue(stderr.isEmpty)
    let attributes = try FileManager.default.attributesOfItem(atPath: log.fileURL.path)
    XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
  }

  func testBoundsFileByTruncatingOldRecordsAndPreservingNewestLine() throws {
    let home = try temporaryHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let log = InputDiagnosticsLog(
      homeDirectory: home, maximumBytes: 80, writeToStdout: { _ in }, writeToStderr: { _ in })

    log.emit("timestamp_utc=2026-10-15T12:00:00Z input-diagnostics old")
    log.emit("timestamp_utc=2026-10-15T12:00:10Z input-diagnostics newest")

    let contents = try String(contentsOf: log.fileURL, encoding: .utf8)
    XCTAssertLessThanOrEqual(contents.utf8.count, 80)
    XCTAssertFalse(contents.contains("old"))
    XCTAssertTrue(contents.contains("newest"))
  }

  func testRejectsMultilineRecordWithoutPersistingInjectedText() throws {
    let home = try temporaryHome()
    defer { try? FileManager.default.removeItem(at: home) }
    var stdout: [String] = []
    var stderr: [String] = []
    let log = InputDiagnosticsLog(
      homeDirectory: home,
      writeToStdout: { stdout.append($0) },
      writeToStderr: { stderr.append($0) })

    log.emit("input-diagnostics\nconfigured-command-output")

    XCTAssertTrue(stdout.isEmpty)
    XCTAssertEqual(stderr.count, 1)
    XCTAssertFalse(FileManager.default.fileExists(atPath: log.fileURL.path))
  }

  func testRejectsSymlinkAndKeepsStdoutDiagnosticsAvailable() throws {
    let home = try temporaryHome()
    defer { try? FileManager.default.removeItem(at: home) }
    let path = home.appendingPathComponent("Library/Logs/aerospace-gestures", isDirectory: true)
    try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
    let target = home.appendingPathComponent("outside.log")
    try Data("keep".utf8).write(to: target)
    let file = path.appendingPathComponent("input-diagnostics.log")
    try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)
    var stdout: [String] = []
    var stderr: [String] = []
    let log = InputDiagnosticsLog(
      homeDirectory: home,
      writeToStdout: { stdout.append($0) },
      writeToStderr: { stderr.append($0) })
    let line = "timestamp_utc=2026-10-15T12:00:00Z input-diagnostics accepted_frames=8"

    log.emit(line)
    log.emit(line)

    XCTAssertEqual(stdout, ["\(line)\n", "\(line)\n"])
    XCTAssertEqual(stderr.count, 1)
    XCTAssertTrue(stderr[0].contains(file.path))
    XCTAssertTrue(stderr[0].contains("stdout"))
    XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "keep")
  }

  private func temporaryHome() throws -> URL {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
    return root
  }
}
