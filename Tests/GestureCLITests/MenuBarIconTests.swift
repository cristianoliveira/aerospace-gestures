import AppKit
import XCTest

@testable import GestureCLI

final class MenuBarIconTests: XCTestCase {
  func testEnabledIconIsAccessibleTemplateAtMenuBarSize() {
    let image = MenuBarIcon.image(isPaused: false, accessibilityDescription: "Actions enabled")

    XCTAssertTrue(image.isTemplate)
    XCTAssertEqual(image.size, NSSize(width: 22, height: 22))
    XCTAssertEqual(image.accessibilityDescription, "Actions enabled")
  }

  func testEnabledIconRendersAMarkOnTransparentBackground() throws {
    let image = MenuBarIcon.image(isPaused: false, accessibilityDescription: "Actions enabled")

    let alpha = try renderedAlpha(image)

    XCTAssertTrue(alpha.contains { $0 > 0 })
    XCTAssertTrue(alpha.contains { $0 == 0 })
  }

  func testPausedIconAddsVisibleBadgeWithoutRemovingTheBrandMark() throws {
    let enabled = MenuBarIcon.image(isPaused: false, accessibilityDescription: "Actions enabled")
    let paused = MenuBarIcon.image(isPaused: true, accessibilityDescription: "Actions paused")

    let enabledAlpha = try renderedAlpha(enabled)
    let pausedAlpha = try renderedAlpha(paused)

    XCTAssertTrue(paused.isTemplate)
    XCTAssertEqual(paused.size, enabled.size)
    XCTAssertEqual(paused.accessibilityDescription, "Actions paused")
    XCTAssertNotEqual(pausedAlpha, enabledAlpha)
    XCTAssertTrue(zip(enabledAlpha, pausedAlpha).allSatisfy { $0 <= $1 })
    XCTAssertGreaterThan(pausedAlpha.reduce(0, +), enabledAlpha.reduce(0, +))
  }

  private func renderedAlpha(_ image: NSImage) throws -> [CGFloat] {
    let bitmap = try XCTUnwrap(
      NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 44, pixelsHigh: 44,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    bitmap.size = image.size
    let context = try XCTUnwrap(NSGraphicsContext(bitmapImageRep: bitmap))
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = context
    image.draw(in: NSRect(origin: .zero, size: image.size))

    return try (0..<44).flatMap { y in
      try (0..<44).map { x in
        try XCTUnwrap(bitmap.colorAt(x: x, y: y)).alphaComponent
      }
    }
  }
}
