import Foundation

/// User preferences, shared between the container app and the QuickLook
/// extension through a file in the extension's sandbox container — see
/// `storeURL`.
///
/// QuickLook can invoke the extension before the app has ever been launched,
/// so every field has a hardcoded default and loading never fails.
public struct PreviewSettings: Codable, Equatable, Sendable {
  public enum ColorMode: String, Codable, Sendable, CaseIterable {
    case system, light, dark
  }

  /// CSS/AppKit font family name. Bundled and user-picked fonts resolve the
  /// same way, so there is no separate "custom" case to branch on.
  public var fontFamily: String
  /// Integer zoom. Pixel fonts only stay crisp at whole multiples of their
  /// design height, so this is a multiplier rather than a point size.
  public var fontScale: Int
  public var colorMode: ColorMode

  /// One text/background pair per appearance, as `#rrggbb`. They are
  /// independent — `colorMode` selects a pair, it does not invert one.
  public var lightForeground: String
  public var lightBackground: String
  public var darkForeground: String
  public var darkBackground: String

  /// Shipped inside the extension, all from the same pack under one license.
  /// Only the text-mode cells `.nfo` art was actually drawn on — the PxPlus
  /// variants add Unicode coverage past CP437, which the decoder never emits.
  public static let bundledFontFamilies = [
    "Px437 IBM VGA 8x16",  // 80x25, what most .nfo art targets
    "Px437 IBM VGA 9x16",  // the true VGA cell, one pixel wider
    "Px437 IBM VGA 9x8",  // 80x50 mode
    "Px437 IBM EGA 8x14",  // EGA-era art
  ]
  public static let defaultFontFamily = bundledFontFamilies[0]
  /// Black on silver light, silver on black dark — the DOS console default
  /// either way round.
  public static let defaultLightForeground = "#000000"
  public static let defaultLightBackground = "#c0c0c0"  // CSS "silver"
  public static let defaultDarkForeground = "#c0c0c0"
  public static let defaultDarkBackground = "#000000"
  public static let fontScales = [1, 2, 3]

  /// The bundled files are named for their family, underscored. `nil` for a
  /// family we do not ship — the caller falls back to the default.
  public static func bundledResource(for family: String) -> String? {
    guard bundledFontFamilies.contains(family) else { return nil }
    return family.replacingOccurrences(of: " ", with: "_")
  }

  public init(
    fontFamily: String = defaultFontFamily,
    fontScale: Int = 1,
    colorMode: ColorMode = .system,
    lightForeground: String = defaultLightForeground,
    lightBackground: String = defaultLightBackground,
    darkForeground: String = defaultDarkForeground,
    darkBackground: String = defaultDarkBackground
  ) {
    self.fontFamily = fontFamily
    self.fontScale = fontScale
    self.colorMode = colorMode
    self.lightForeground = lightForeground
    self.lightBackground = lightBackground
    self.darkForeground = darkForeground
    self.darkBackground = darkBackground
  }

  public static let extensionBundleID = "com.idleberg.QuicklookNFO.QuicklookExtension"

  /// Both sides agree on one file inside the *extension's* sandbox container.
  ///
  /// An App Group is the sanctioned channel, but that entitlement needs a
  /// provisioning profile from a paid Apple Developer team. An app extension
  /// must be sandboxed; its container app need not be — so the app reaches
  /// into the extension's container and leaves the file there, and the
  /// extension reads it as an ordinary file in its own home.
  public static var storeURL: URL {
    let home = URL(fileURLWithPath: NSHomeDirectory())
    // A sandboxed process's home already *is* its container.
    let container =
      home.path.contains("/Library/Containers/")
      ? home
      : home.appending(path: "Library/Containers/\(extensionBundleID)/Data")
    return container.appending(path: "Library/Application Support/PreviewSettings.json")
  }

  public static func load(from url: URL = storeURL) -> PreviewSettings {
    guard let data = try? Data(contentsOf: url),
      let settings = try? JSONDecoder().decode(PreviewSettings.self, from: data)
    else {
      return PreviewSettings()
    }
    return settings
  }

  public func save(to url: URL = Self.storeURL) {
    let directory = url.deletingLastPathComponent()
    // "Application Support" is ours to create, but the container itself is
    // not: macOS builds that on the extension's first run, and a hand-made
    // one breaks its sandbox setup. Until then saving is a no-op and the
    // extension renders with the defaults.
    guard FileManager.default.fileExists(atPath: directory.deletingLastPathComponent().path),
      let data = try? JSONEncoder().encode(self)
    else { return }
    try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    try? data.write(to: url)
  }
}
