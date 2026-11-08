import AppKit

/// Cafuné's fingertip-and-motion mark, drawn in the binary so CLI installs need no resource bundle.
enum MenuBarIcon {
  static func image(isPaused: Bool, accessibilityDescription: String) -> NSImage {
    let size = NSSize(width: 22, height: 22)
    let image = NSImage(size: size, flipped: true) { _ in
      guard let context = NSGraphicsContext.current?.cgContext else { return false }
      context.saveGState()
      defer { context.restoreGState() }
      context.scaleBy(x: size.width / 256, y: size.height / 256)
      context.setStrokeColor(NSColor.black.cgColor)
      context.setLineWidth(24)
      context.setLineCap(.round)
      context.setLineJoin(.round)

      // The same 256-point flowing C and fingertip accent as docs/brand/logo.svg.
      context.move(to: CGPoint(x: 180, y: 70))
      context.addCurve(
        to: CGPoint(x: 113, y: 39), control1: CGPoint(x: 159, y: 40),
        control2: CGPoint(x: 134, y: 34))
      context.addCurve(
        to: CGPoint(x: 39, y: 119), control1: CGPoint(x: 68, y: 45),
        control2: CGPoint(x: 39, y: 76))
      context.addCurve(
        to: CGPoint(x: 117, y: 218), control1: CGPoint(x: 39, y: 165),
        control2: CGPoint(x: 73, y: 214))
      context.addCurve(
        to: CGPoint(x: 188, y: 174), control1: CGPoint(x: 159, y: 222),
        control2: CGPoint(x: 184, y: 199))
      context.strokePath()

      context.setFillColor(NSColor.black.cgColor)
      context.fillEllipse(in: CGRect(x: 187, y: 45, width: 22, height: 22))

      if isPaused {
        context.setLineWidth(17)
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
