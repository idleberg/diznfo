import AppKit
import NFOKit
import SwiftUI

/// `PreviewSettings` stores `#rrggbb` because the extension interpolates it
/// into CSS; AppKit and SwiftUI both want a color object.
extension NSColor {
  convenience init(hex: String) {
    let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
    self.init(
      srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
      green: CGFloat((value >> 8) & 0xFF) / 255,
      blue: CGFloat(value & 0xFF) / 255,
      alpha: 1
    )
  }
}

extension Color {
  init(hex: String) {
    self.init(nsColor: NSColor(hex: hex))
  }

  var hex: String {
    guard let rgb = NSColor(self).usingColorSpace(.sRGB) else {
      return PreviewSettings.defaultLightForeground
    }
    let channel = { (value: CGFloat) in Int((value * 255).rounded()) }
    return String(
      format: "#%02x%02x%02x", channel(rgb.redComponent), channel(rgb.greenComponent),
      channel(rgb.blueComponent))
  }
}
