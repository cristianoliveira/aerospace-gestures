import Darwin
import Foundation
import XCTest

@testable import GestureInfrastructure

final class CommandOutputLogTests: XCTestCase {
  func testAppendsTaggedOutputWithPrivatePermissionsAndBoundsTotalSize() throws {
    let root = try temporaryHome()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = logURL(under: root)
    let log = CommandOutputLog(fileURL: file, rootURL: root, maximumBytes: 64)

    try log.append(Data(String(repeating: "x", count: 100).utf8), from: .stdout)
    try log.append(Data("latest error".utf8), from: .stderr)

    let contents = try Data(contentsOf: file)
    XCTAssertLessThanOrEqual(contents.count, 64)
    XCTAssertTrue(String(decoding: contents, as: UTF8.self).contains("[stderr] latest error"))
    let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
    XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
  }

  func testRejectsSymlinkedLogFile() throws {
    let root = try temporaryHome()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = logURL(under: root)
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    let target = root.appendingPathComponent("outside.log")
    try Data("keep".utf8).write(to: target)
    try FileManager.default.createSymbolicLink(at: file, withDestinationURL: target)

    XCTAssertThrowsError(
      try CommandOutputLog(fileURL: file, rootURL: root).append(Data("secret".utf8), from: .stdout))
    XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "keep")
  }

  func testRejectsExistingWorldReadableLogFileWithoutChangingIt() throws {
    let root = try temporaryHome()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = logURL(under: root)
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    let original = Data("do not expose".utf8)
    try original.write(to: file)
    try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file.path)

    XCTAssertThrowsError(
      try CommandOutputLog(fileURL: file, rootURL: root).append(Data("secret".utf8), from: .stdout))
    XCTAssertEqual(try Data(contentsOf: file), original)
    let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
    XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o644)
  }

  func testRejectsGroupWritableParentDirectory() throws {
    let root = try temporaryHome()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = logURL(under: root)
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o770], ofItemAtPath: file.deletingLastPathComponent().path)

    XCTAssertThrowsError(
      try CommandOutputLog(fileURL: file, rootURL: root).append(Data("secret".utf8), from: .stdout))
    XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
  }

  func testRejectsFIFOWithoutBlocking() throws {
    let root = try temporaryHome()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = logURL(under: root)
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    XCTAssertEqual(mkfifo(file.path, mode_t(0o600)), 0)

    XCTAssertThrowsError(
      try CommandOutputLog(fileURL: file, rootURL: root).append(Data("secret".utf8), from: .stdout))
    var information = stat()
    XCTAssertEqual(lstat(file.path, &information), 0)
    XCTAssertEqual(information.st_mode & S_IFMT, S_IFIFO)
  }

  func testRejectsHardLinkedLogFile() throws {
    let root = try temporaryHome()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = logURL(under: root)
    try FileManager.default.createDirectory(
      at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("existing".utf8).write(to: file)
    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    let otherLink = root.appendingPathComponent("other.log")
    XCTAssertEqual(link(file.path, otherLink.path), 0)

    XCTAssertThrowsError(
      try CommandOutputLog(fileURL: file, rootURL: root).append(Data("secret".utf8), from: .stdout))
  }

  func testRejectsSymlinkedParentDirectory() throws {
    let root = try temporaryHome()
    defer { try? FileManager.default.removeItem(at: root) }
    let file = logURL(under: root)
    let external = root.appendingPathComponent("external", isDirectory: true)
    try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(
      at: root.appendingPathComponent("Library"), withDestinationURL: external)

    XCTAssertThrowsError(
      try CommandOutputLog(fileURL: file, rootURL: root).append(Data("secret".utf8), from: .stdout))
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: external.appendingPathComponent(
          "Application Support/aerospace-gestures/command-output.log"
        ).path))
  }

  private func temporaryHome() throws -> URL {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
    return root
  }

  private func logURL(under root: URL) -> URL {
    root.appendingPathComponent(
      "Library/Application Support/aerospace-gestures/command-output.log")
  }
}
