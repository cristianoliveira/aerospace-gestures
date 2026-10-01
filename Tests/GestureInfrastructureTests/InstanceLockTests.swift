import Foundation
import XCTest

@testable import GestureInfrastructure

final class InstanceLockTests: XCTestCase {
  func testLockIsExclusiveAndReleasedOnExplicitRelease() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let path = directory.appendingPathComponent("support/instance.lock")
    let first = try InstanceLock.acquire(at: path, under: directory)

    XCTAssertThrowsError(try InstanceLock.acquire(at: path, under: directory)) { error in
      XCTAssertTrue(error is InstanceLockError)
      XCTAssertTrue(String(describing: error).contains("already holds"))
    }

    first.release()
    let second = try InstanceLock.acquire(at: path, under: directory)
    second.release()
    XCTAssertTrue(FileManager.default.fileExists(atPath: path.path))
    let attributes = try FileManager.default.attributesOfItem(atPath: path.path)
    XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
  }

  func testManagedListenerCanWaitForAnExistingListenerToReleaseLock() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let path = directory.appendingPathComponent("support/instance.lock")
    let foreground = try InstanceLock.acquire(at: path, under: directory)
    var waitCount = 0

    let managed = try InstanceLock.acquire(
      at: path, under: directory, waitForContention: true,
      sleep: { _ in
        waitCount += 1
        foreground.release()
      })

    XCTAssertEqual(waitCount, 1)
    managed.release()
  }

  func testRejectsLockPathDirectoryOwnedByAnotherUIDBeforeCreatingChildren() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let lockPath = directory.appendingPathComponent("support/listener.lock")

    XCTAssertThrowsError(
      try InstanceLock.acquire(
        at: lockPath, under: directory, ownerUID: getuid() + 1))
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: directory.appendingPathComponent("support").path))
  }

  func testRejectsGroupWorldWritableAncestorBeforeCreatingDescendants() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let unsafe = directory.appendingPathComponent("unsafe", isDirectory: true)
    try FileManager.default.createDirectory(at: unsafe, withIntermediateDirectories: true)
    try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: unsafe.path)
    let lockPath = unsafe.appendingPathComponent("nested/listener.lock")

    XCTAssertThrowsError(try InstanceLock.acquire(at: lockPath, under: directory))
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: unsafe.appendingPathComponent("nested").path))
  }

  func testAncestorSymlinkIsRejectedBeforeCreatingOutsideDirectory() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let outside = directory.appendingPathComponent("outside", isDirectory: true)
    let redirected = directory.appendingPathComponent("redirected", isDirectory: true)
    try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
    try FileManager.default.createSymbolicLink(at: redirected, withDestinationURL: outside)
    let lockPath = redirected.appendingPathComponent("nested/listener.lock")

    XCTAssertThrowsError(try InstanceLock.acquire(at: lockPath, under: directory))
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: outside.appendingPathComponent("nested").path))
  }

  func testLockFileSymlinkIsRejectedWithoutChangingItsTarget() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let target = directory.appendingPathComponent("target")
    let lockPath = directory.appendingPathComponent("listener.lock")
    try Data("user data".utf8).write(to: target)
    try FileManager.default.createSymbolicLink(at: lockPath, withDestinationURL: target)

    XCTAssertThrowsError(try InstanceLock.acquire(at: lockPath, under: directory))
    XCTAssertEqual(try Data(contentsOf: target), Data("user data".utf8))
  }
}
