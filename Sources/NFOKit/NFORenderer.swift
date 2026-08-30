import Foundation

/// Turns raw `.nfo`/`.diz` bytes into a self-contained HTML page for `WKWebView`.
public enum NFORenderer {
  /// Fallback when a file carries no SAUCE width hint.
  public static let defaultColumns = 80

  public struct Palette: Equatable, Sendable {
    public var foreground: String
    public var background: String

    /// Each appearance has its own pair — the dark one is not derived from the
    /// light one, so a user can set, say, amber-on-black without that dictating
    /// their light colors. `.system` picks which pair from the host appearance
    /// at render time.
    public static func resolve(_ settings: PreviewSettings, isDarkAppearance: Bool) -> Palette {
      let isDark: Bool
      switch settings.colorMode {
      case .light: isDark = false
      case .dark: isDark = true
      case .system: isDark = isDarkAppearance
      }
      return Palette(
        foreground: sanitize(
          isDark ? settings.darkForeground : settings.lightForeground,
          fallback: isDark
            ? PreviewSettings.defaultDarkForeground : PreviewSettings.defaultLightForeground),
        background: sanitize(
          isDark ? settings.darkBackground : settings.lightBackground,
          fallback: isDark
            ? PreviewSettings.defaultDarkBackground : PreviewSettings.defaultLightBackground)
      )
    }

    /// Colors are interpolated straight into a stylesheet, so anything that is
    /// not a literal `#rrggbb` is replaced rather than escaped.
    private static func sanitize(_ color: String, fallback: String) -> String {
      let isHex =
        color.count == 7 && color.hasPrefix("#")
        && color.dropFirst().allSatisfy(\.isHexDigit)
      return isHex ? color : fallback
    }
  }

  /// Precedence: width comes from SAUCE when present (it is structural — the
  /// art was drawn for that column count), font and colors always come from
  /// the user's settings (those are aesthetic).
  ///
  /// - Parameters:
  ///   - font: a bundled font's family name and file bytes, embedded as a
  ///     `data:` URI. WebKit refuses to read sibling files for a
  ///     `loadHTMLString` page, so linking the resource by name silently falls
  ///     back to a system font. `nil` falls back to whatever
  ///     `settings.fontFamily` is installed.
  ///   - isDarkAppearance: the host's appearance, used only by `.system` to
  ///     decide whether to invert the user's color pair.
  public static func html(
    for data: Data,
    settings: PreviewSettings,
    font: (family: String, data: Data)? = nil,
    isDarkAppearance: Bool = true
  ) -> String {
    let (content, sauce) = SauceRecord.split(data)
    let text = CP437.decode(content)
    let columns = sauce?.width ?? defaultColumns

    let palette = Palette.resolve(settings, isDarkAppearance: isDarkAppearance)

    // The @font-face declares the family the *file* actually is, never the
    // user's pick — otherwise choosing "Menlo" would serve a bundled file
    // under that name. A user pick is looked up system-wide and falls back
    // to whichever bundled family is embedded here.
    let embedded = font?.family ?? PreviewSettings.defaultFontFamily
    let fontFace =
      font.map {
        """
        @font-face {
          font-family: "\(escape($0.family))";
          src: url("data:font/ttf;base64,\($0.data.base64EncodedString())");
        }
        """
      } ?? ""

    return """
      <!DOCTYPE html>
      <html><head><meta charset="utf-8"><style>
      \(fontFace)
      html, body {
        margin: 0;
        padding: 0;
        background: \(palette.background);
        color: \(palette.foreground);
      }
      pre {
        margin: 0;
        padding: 1em;
        font-family: "\(escape(settings.fontFamily))",
                     "\(escape(embedded))",
                     ui-monospace, monospace;
        font-size: \(pixelSize(settings))px;
        line-height: 1.0;
        white-space: pre;
        width: \(columns)ch;
        -webkit-font-smoothing: none;
        font-variant-ligatures: none;
      }
      </style></head><body><pre>\(escape(text))</pre></body></html>
      """
  }

  /// A pixel font is only crisp at whole multiples of its design height, and
  /// the int10h families carry that height in their `WxH` cell suffix. A font
  /// with no such suffix (any system pick) gets the 16px VGA height.
  static func pixelSize(_ settings: PreviewSettings) -> Int {
    let height = settings.fontFamily.split(separator: "x").last.flatMap { Int($0) } ?? 16
    // The scale reaches here from a JSON file on disk, so it is clamped.
    return height * min(max(settings.fontScale, 1), PreviewSettings.fontScales.max()!)
  }

  private static func escape(_ string: String) -> String {
    string
      .replacingOccurrences(of: "&", with: "&amp;")
      .replacingOccurrences(of: "<", with: "&lt;")
      .replacingOccurrences(of: ">", with: "&gt;")
      .replacingOccurrences(of: "\"", with: "&quot;")
  }
}
