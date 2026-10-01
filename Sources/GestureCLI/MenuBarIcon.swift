import AppKit

/// Triple Swipe, drawn into the binary so CLI installs need no resource bundle.
enum MenuBarIcon {
  static func image(isPaused: Bool, accessibilityDescription: String) -> NSImage {
    let size = NSSize(width: 22, height: 22)
    let image = NSImage(size: size, flipped: true) { _ in
      guard let context = NSGraphicsContext.current?.cgContext else { return false }
      context.saveGState()
      defer { context.restoreGState() }
      context.scaleBy(x: size.width / 256, y: size.height / 256)
      context.setStrokeColor(NSColor.black.cgColor)
      context.setLineWidth(17)
      context.setLineCap(.round)
      context.setLineJoin(.round)

      // Same 256-point geometry as docs/brand/triple-swipe.svg.
      context.move(to: CGPoint(x: 55, y: 83))
      context.addLine(to: CGPoint(x: 105, y: 83))
      context.addQuadCurve(to: CGPoint(x: 161, y: 59), control: CGPoint(x: 141, y: 83))
      context.addLine(to: CGPoint(x: 181, y: 39))

      context.move(to: CGPoint(x: 55, y: 136))
      context.addLine(to: CGPoint(x: 111, y: 136))
      context.addQuadCurve(to: CGPoint(x: 171, y: 112), control: CGPoint(x: 147, y: 136))
      context.addLine(to: CGPoint(x: 214, y: 69))
      context.move(to: CGPoint(x: 179, y: 69))
      context.addLine(to: CGPoint(x: 214, y: 69))
      context.addLine(to: CGPoint(x: 214, y: 104))

      context.move(to: CGPoint(x: 55, y: 189))
      context.addLine(to: CGPoint(x: 115, y: 189))
      context.addQuadCurve(to: CGPoint(x: 176, y: 164), control: CGPoint(x: 151, y: 189))
      context.addLine(to: CGPoint(x: 199, y: 141))
      context.strokePath()

      if isPaused {
        context.move(to: CGPoint(x: 182, y: 204))
        context.addLine(to: CGPoint(x: 182, y: 237))
        context.move(to: CGPoint(x: 218, y: 204))
        context.addLine(to: CGPoint(x: 218, y: 237))
        context.strokePath()
      }
      return true
    }
    image.isTemplate = true
    image.accessibilityDescription = accessibilityDescription
    return image
  }
}
