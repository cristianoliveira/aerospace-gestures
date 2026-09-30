import Darwin
import Foundation
import XCTest

@testable import GestureInfrastructure

final class StartupDiagnosticStoreTests: XCTestCase {
  func testStoresOnlyFixedPrivateDiagnosticAndOverwritesItWithinTheCap() throws {
    let fixture = try DiagnosticFixture()
    defer { fixture.remove() }
    let store = StartupDiagnosticStore(fileURL: fixture.fileURL, rootURL: fixture.root)

    try store.record(.configurationValidationFailed)
    try store.record(.inputInitializationFailed)

    XCTAssertEqual(try store.read(), .inputInitializationFailed)
    let data = try Data(contentsOf: fixture.fileURL)
    XCTAssertLessThanOrEqual(data.count, StartupDiagnosticStore.maximumBytes)
    XCTAssertEqual(
      String(decoding: data, as: UTF8.self),
      "version=1\nstage=input-initialization\ncategory=failed\n")
    let attributes = try FileManager.default.attributesOfItem(atPath: fixture.fileURL.path)
    XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
  }

  func testClearRemovesOnlyTheDiagnosticRecord() throws {
    let fixture = try DiagnosticFixture()
    defer { fixture.remove() }
    let store = StartupDiagnosticStore(fileURL: fixture.fileURL, rootURL: fixture.root)
    let unrelated = fixture.directory.appendingPathComponent("keep.txt")
    try Data("user data".utf8).write(to: unrelated)
    try store.record(.inputInitializationFailed)

    try store.clear()

    XCTAssertNil(try store.read())
    XCTAssertEqual(try String(contentsOf: unrelated, encoding: .utf8), "user data")
  }

  func testRefusesDiagnosticSymlinkWithoutChangingItsTarget() throws {
    let fixture = try DiagnosticFixture()
    defer { fixture.remove() }
    let target = fixture.directory.appendingPathComponent("outside.txt")
    let original = Data("do not replace".utf8)
    try original.write(to: target)
    try FileManager.default.createSymbolicLink(at: fixture.fileURL, withDestinationURL: target)
    let store = StartupDiagnosticStore(fileURL: fixture.fileURL, rootURL: fixture.root)

    XCTAssertThrowsError(try store.record(.inputInitializationFailed))

    XCTAssertEqual(try Data(contentsOf: target), original)
  }

  func testRejectsSymlinkInDiagnosticDirectoryChain() throws {
    let fixture = try DiagnosticFixture()
    defer { fixture.remove() }
    let alias = fixture.root.appendingPathComponent("alias", isDirectory: true)
    try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: fixture.directory)
    let redirectedFile = alias.appendingPathComponent("startup-diagnostic.log")
    let store = StartupDiagnosticStore(fileURL: redirectedFile, rootURL: fixture.root)

    XCTAssertThrowsError(try store.record(.inputInitializationFailed))
    XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.fileURL.path))
  }

  func testMapsKnownInputFailuresWithoutRetainingTheirText() throws {
    let fixture = try DiagnosticFixture()
    defer { fixture.remove() }
    let messages: [(String, StartupDiagnostic)] = [
      (
        "Cannot load private MultitouchSupport framework on this macOS version",
        .privateFrameworkUnavailable
      ),
      (
        "Required private multitouch symbols are unavailable on this macOS version",
        .privateSymbolsUnavailable
      ),
      ("No multitouch devices found; connect a trackpad and retry", .noMultitouchDevices),
      ("secret details must not be stored", .inputInitializationFailed),
    ]
    let store = StartupDiagnosticStore(fileURL: fixture.fileURL, rootURL: fixture.root)

    for (message, expected) in messages {
      let diagnostic = StartupDiagnostic.inputInitializationFailure(for: message)
      XCTAssertEqual(diagnostic, expected)
      try store.record(diagnostic)
      XCTAssertFalse(try String(contentsOf: fixture.fileURL, encoding: .utf8).contains(message))
    }
  }

  func testReadAndClearRejectFifoWithoutBlocking() throws {
    let fixture = try DiagnosticFixture()
    defer { fixture.remove() }
    XCTAssertEqual(mkfifo(fixture.fileURL.path, mode_t(0o600)), 0)
    let store = StartupDiagnosticStore(fileURL: fixture.fileURL, rootURL: fixture.root)
    let readFinished = expectation(description: "FIFO read is rejected without blocking")

    DispatchQueue.global().async {
      do {
        _ = try store.read()
        XCTFail("FIFO read should be rejected")
      } catch {}
      readFinished.fulfill()
    }
    wait(for: [readFinished], timeout: 1)

    let clearFinished = expectation(description: "FIFO clear is rejected without blocking")
    DispatchQueue.global().async {
      do {
        try store.clear()
        XCTFail("FIFO clear should be rejected")
      } catch {}
      clearFinished.fulfill()
    }
    wait(for: [clearFinished], timeout: 1)
  }

  func testRefusesToOverwriteUnrecognizedPrivateFile() throws {
    let fixture = try DiagnosticFixture()
    defer { fixture.remove() }
    let original = Data("unrelated data".utf8)
    try original.write(to: fixture.fileURL)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600], ofItemAtPath: fixture.fileURL.path)
    let store = StartupDiagnosticStore(fileURL: fixture.fileURL, rootURL: fixture.root)

    XCTAssertThrowsError(try store.record(.inputInitializationFailed))
    XCTAssertThrowsError(try store.clear())

    XCTAssertEqual(try Data(contentsOf: fixture.fileURL), original)
  }

  func testRejectsMalformedOrOversizedDiagnostic() throws {
    let fixture = try DiagnosticFixture()
    defer { fixture.remove() }
    let store = StartupDiagnosticStore(fileURL: fixture.fileURL, rootURL: fixture.root)
    let oversized = Data(repeating: 0x61, count: StartupDiagnosticStore.maximumBytes + 1)
    try oversized.write(to: fixture.fileURL)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o600], ofItemAtPath: fixture.fileURL.path)

    XCTAssertThrowsError(try store.read())
  }
}

private final class DiagnosticFixture {
  let root = FileManager.default.temporaryDirectory
    .appendingPathComponent(UUID().uuidString, isDirectory: true)
  var directory: URL { root.appendingPathComponent("support", isDirectory: true) }
  var fileURL: URL { directory.appendingPathComponent("startup-diagnostic.log") }

  init() throws {
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)
  }

  func remove() { try? FileManager.default.removeItem(at: root) }
}
