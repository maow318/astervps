import AppKit

/// Procedurally drawn textures for the globe. Generating them beats bundling
/// artwork: no licensing, no download, and they follow the accent color.
enum GlobeArt {
  private static var cache: [String: NSImage] = [:]

  /// Equirectangular starfield standing in for the reference's Milky Way
  /// backdrop.
  static func starfield() -> NSImage {
    cached("stars") {
      let size = NSSize(width: 4096, height: 2048)
      let image = NSImage(size: size)
      image.lockFocus()
      NSColor.black.setFill()
      NSRect(origin: .zero, size: size).fill()

      var seed: UInt64 = 0x5DEE_CE66
      func random() -> Double {
        seed = seed &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double((seed >> 33) % 100_000) / 100_000
      }
      for _ in 0..<11000 {
        let x = random() * size.width
        let y = random() * size.height
        let bright = random()
        let radius = bright > 0.99 ? 1.5 : (bright > 0.93 ? 1.0 : 0.6)
        let alpha = 0.2 + bright * 0.75
        NSColor(white: 0.85 + bright * 0.15, alpha: alpha).setFill()
        NSBezierPath(
          ovalIn: NSRect(x: x, y: y, width: radius * 2, height: radius * 2)
        ).fill()
      }
      image.unlockFocus()
      return image
    }
  }

  static func flagImage(_ flag: String, glow: NSColor) -> NSImage {
    cached("flag-\(flag)-\(glow.description)") {
      let size = NSSize(width: 256, height: 180)
      let image = NSImage(size: size)
      image.lockFocus()
      let shadow = NSShadow()
      shadow.shadowColor = glow.withAlphaComponent(0.9)
      shadow.shadowBlurRadius = 22
      shadow.shadowOffset = .zero
      shadow.set()
      let text = flag as NSString
      let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 130)]
      let bounds = text.size(withAttributes: attributes)
      text.draw(
        at: NSPoint(x: (size.width - bounds.width) / 2, y: (size.height - bounds.height) / 2),
        withAttributes: attributes)
      image.unlockFocus()
      return image
    }
  }

  /// Soft ring used for the expanding pulse under each marker.
  static func ringImage(_ color: NSColor) -> NSImage {
    cached("ring-\(color.description)") {
      let size = NSSize(width: 256, height: 256)
      let image = NSImage(size: size)
      image.lockFocus()
      let path = NSBezierPath(ovalIn: NSRect(x: 18, y: 18, width: 220, height: 220))
      path.lineWidth = 16
      color.withAlphaComponent(0.85).setStroke()
      path.stroke()
      image.unlockFocus()
      return image
    }
  }

  /// Filled dot with a halo for this Mac's own position.
  static func homeImage(_ color: NSColor) -> NSImage {
    cached("home-\(color.description)") {
      let size = NSSize(width: 256, height: 256)
      let image = NSImage(size: size)
      image.lockFocus()
      color.withAlphaComponent(0.28).setFill()
      NSBezierPath(ovalIn: NSRect(x: 40, y: 40, width: 176, height: 176)).fill()
      NSColor.white.setFill()
      NSBezierPath(ovalIn: NSRect(x: 98, y: 98, width: 60, height: 60)).fill()
      color.setStroke()
      let ring = NSBezierPath(ovalIn: NSRect(x: 92, y: 92, width: 72, height: 72))
      ring.lineWidth = 10
      ring.stroke()
      image.unlockFocus()
      return image
    }
  }

  /// One dash cell: lit half, gap half. Repeated along each arc and scrolled.
  static func dashImage(_ color: NSColor) -> NSImage {
    cached("dash-\(color.description)") {
      let size = NSSize(width: 64, height: 8)
      let image = NSImage(size: size)
      image.lockFocus()
      NSColor.clear.setFill()
      NSRect(origin: .zero, size: size).fill()
      let gradient = NSGradient(colors: [
        color.withAlphaComponent(0.0), color.withAlphaComponent(1.0),
        color.withAlphaComponent(0.0),
      ])
      gradient?.draw(in: NSRect(x: 0, y: 0, width: 34, height: size.height), angle: 0)
      image.unlockFocus()
      return image
    }
  }

  private static func cached(_ key: String, _ build: () -> NSImage) -> NSImage {
    if let hit = cache[key] { return hit }
    let image = build()
    cache[key] = image
    return image
  }
}
