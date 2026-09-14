import Foundation
import Testing

@testable import NFOKit

@Suite("CP437")
struct CP437Tests {
  @Test("maps the box-drawing and control-range glyphs DOS art relies on")
  func knownGlyphs() {
    #expect(CP437.decode([0xDB, 0xB0, 0xC4, 0xB3, 0xDA]) == "█░─│┌")
    #expect(CP437.decode([0x01, 0x10, 0x1F]) == "☺►▼")
    #expect(CP437.decode([0x41, 0x7A, 0x20]) == "Az ")
    #expect(CP437.decode([0xE1, 0xFE]) == "ß■")
    #expect(CP437.decode([0xFF]) == "\u{00A0}")
  }

  @Test("normalizes DOS line endings")
  func lineEndings() {
    #expect(CP437.decode(Array("a\r\nb\rc\nd".utf8)) == "a\nb\nc\nd")
    #expect(CP437.decode([0x0A, 0x0A]) == "\n\n")
    #expect(CP437.decode([0x09]) == "\t")
  }

  @Test("encodes back to the bytes it decoded from")
  func roundTrip() {
    // Every byte except 0x00 and 0x0D: 0x00 draws the same space as 0x20, and
    // a lone CR is normalized to LF on the way in — neither survives a trip.
    let bytes = (0...255).map(UInt8.init).filter { $0 != 0x00 && $0 != 0x0D }
    #expect(Array(CP437.encode(CP437.decode(bytes))) == bytes)
  }

  @Test("writes the ASCII byte for a glyph two bytes share, and ? for the rest")
  func encodeFallbacks() {
    #expect(Array(CP437.encode(" ")) == [0x20])  // not 0x00
    #expect(Array(CP437.encode("héllo")) == [0x68, 0x82, 0x6C, 0x6C, 0x6F])
    #expect(Array(CP437.encode("日🎉")) == [0x3F, 0x3F])
    // The caller owns line endings; encode passes through whatever it is given.
    #expect(Array(CP437.encode("a\r\nb")) == [0x61, 0x0D, 0x0A, 0x62])
  }
}

@Suite("SAUCE")
struct SauceTests {
  /// Builds a synthetic file: art + optional COMNT block + 128-byte record.
  static func file(art: String, comments: [String] = [], width: UInt16 = 80) -> Data {
    var data = Data(art.utf8)
    data.append(0x1A)  // DOS EOF marker
    if !comments.isEmpty {
      data.append(contentsOf: Array("COMNT".utf8))
      for comment in comments {
        data.append(
          contentsOf: Array(comment.padding(toLength: 64, withPad: " ", startingAt: 0).utf8))
      }
    }
    var record = Data(Array("SAUCE00".utf8))
    func field(_ value: String, _ length: Int) {
      record.append(
        contentsOf: Array(value.padding(toLength: length, withPad: " ", startingAt: 0).utf8))
    }
    field("A Title", 35)
    field("VileR", 20)
    field("ACiD", 20)
    field("19940101", 8)
    record.append(contentsOf: [0, 0, 0, 0])  // FileSize
    record.append(1)  // DataType: character
    record.append(1)  // FileType: ANSi
    record.append(contentsOf: [UInt8(width & 0xFF), UInt8(width >> 8)])  // TInfo1
    record.append(contentsOf: [0, 0, 0, 0, 0, 0])  // TInfo2..4
    record.append(UInt8(comments.count))
    record.append(0b1)  // TFlags: iCE colors
    field("IBM VGA", 22)
    return data + record
  }

  @Test("parses fields and strips the trailer from the art")
  func parsesRecord() {
    let (content, sauce) = SauceRecord.split(Self.file(art: "hello"))
    #expect(String(decoding: content, as: UTF8.self) == "hello")
    #expect(sauce?.title == "A Title")
    #expect(sauce?.author == "VileR")
    #expect(sauce?.group == "ACiD")
    #expect(sauce?.date == "19940101")
    #expect(sauce?.fontName == "IBM VGA")
    #expect(sauce?.width == 80)
    #expect(sauce?.usesICEColors == true)
  }

  @Test("strips a COMNT block ahead of the record")
  func stripsComments() {
    let (content, sauce) = SauceRecord.split(Self.file(art: "art", comments: ["one", "two"]))
    #expect(String(decoding: content, as: UTF8.self) == "art")
    #expect(sauce != nil)
  }

  @Test("degrades gracefully when there is no record")
  func noSauce() {
    let (content, sauce) = SauceRecord.split(Data("just art\u{1A}".utf8))
    #expect(sauce == nil)
    #expect(String(decoding: content, as: UTF8.self) == "just art")
  }

  @Test("ignores a width hint that is absent or non-character data")
  func widthHints() {
    var (_, sauce) = SauceRecord.split(Self.file(art: "x", width: 0))
    #expect(sauce?.width == nil)
    (_, sauce) = SauceRecord.split(Self.file(art: "x", width: 132))
    #expect(sauce?.width == 132)
  }
}

@Suite("PreviewSettings")
struct PreviewSettingsTests {
  /// Mirrors the real layout: a container whose `Library` exists but whose
  /// `Application Support` does not.
  static func container() throws -> URL {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appending(path: "settings-\(UUID().uuidString)")
    try FileManager.default.createDirectory(
      at: root.appending(path: "Library"), withIntermediateDirectories: true)
    return root.appending(path: "Library/Application Support/PreviewSettings.json")
  }

  @Test("falls back to defaults when nothing has been stored yet")
  func defaults() throws {
    #expect(PreviewSettings.load(from: try Self.container()) == PreviewSettings())
  }

  @Test("round-trips through the shared file")
  func roundTrip() throws {
    let url = try Self.container()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let settings = PreviewSettings(fontFamily: "Menlo", colorMode: .light)
    settings.save(to: url)
    #expect(PreviewSettings.load(from: url) == settings)
  }

  @Test("refuses to conjure a sandbox container that macOS has not created")
  func doesNotCreateContainer() {
    let url = URL(fileURLWithPath: NSTemporaryDirectory())
      .appending(path: "absent-\(UUID().uuidString)/Library/Application Support/x.json")
    PreviewSettings(colorMode: .light).save(to: url)
    #expect(!FileManager.default.fileExists(atPath: url.path))
  }

  @Test("resolves to the extension's container from an unsandboxed process")
  func storePath() {
    // Tests run unsandboxed, so this is the app's view of the path.
    #expect(
      PreviewSettings.storeURL.path.contains(
        "Library/Containers/\(PreviewSettings.extensionBundleID)/Data"))
  }
}

@Suite("NFORenderer")
struct NFORendererTests {
  @Test("renders decoded art, honouring the SAUCE width and the user's colors")
  func rendersArt() {
    let art = Data([0xDB, 0xB0, 0x0D, 0x0A, 0x41])
    var file = art
    file.append(SauceTests.file(art: "", width: 132).suffix(128))
    let html = NFORenderer.html(for: file, settings: PreviewSettings(colorMode: .light))
    #expect(html.contains("█░\nA"))
    #expect(html.contains("width: 132ch"))
    #expect(html.contains("background: \(PreviewSettings.defaultLightBackground)"))
  }

  @Test("each appearance uses its own pair, never the other one inverted")
  func colorModes() {
    let chosen = PreviewSettings(
      lightForeground: "#112233", lightBackground: "#445566",
      darkForeground: "#778899", darkBackground: "#aabbcc")
    func resolve(_ mode: PreviewSettings.ColorMode, isDark: Bool) -> NFORenderer.Palette {
      var settings = chosen
      settings.colorMode = mode
      return NFORenderer.Palette.resolve(settings, isDarkAppearance: isDark)
    }
    let light = NFORenderer.Palette(foreground: "#112233", background: "#445566")
    let dark = NFORenderer.Palette(foreground: "#778899", background: "#aabbcc")
    // The explicit modes ignore the host appearance entirely.
    #expect(resolve(.light, isDark: true) == light)
    #expect(resolve(.dark, isDark: false) == dark)
    #expect(resolve(.system, isDark: false) == light)
    #expect(resolve(.system, isDark: true) == dark)
  }

  @Test("defaults to black on silver, and silver on black in the dark")
  func defaultColors() {
    #expect(
      NFORenderer.Palette.resolve(PreviewSettings(), isDarkAppearance: false)
        == .init(foreground: "#000000", background: "#c0c0c0"))
    #expect(
      NFORenderer.Palette.resolve(PreviewSettings(), isDarkAppearance: true)
        == .init(foreground: "#c0c0c0", background: "#000000"))
  }

  @Test("replaces anything that is not a literal hex color, per appearance")
  func rejectsUnsafeColors() {
    let bad = PreviewSettings(
      lightForeground: "red; } body { display: none", lightBackground: "#gggggg",
      darkForeground: "", darkBackground: "#00ff00; }")
    #expect(
      NFORenderer.Palette.resolve(bad, isDarkAppearance: false)
        == .init(foreground: "#000000", background: "#c0c0c0"))
    #expect(
      NFORenderer.Palette.resolve(bad, isDarkAppearance: true)
        == .init(foreground: "#c0c0c0", background: "#000000"))
  }

  @Test("falls back to 80 columns and escapes HTML in the art")
  func escapesAndDefaults() {
    let html = NFORenderer.html(for: Data("<b>&\"</b>".utf8), settings: PreviewSettings())
    #expect(html.contains("width: 80ch"))
    #expect(html.contains("&lt;b&gt;&amp;&quot;&lt;/b&gt;"))
  }

  @Test("renders ANSI art in the VGA palette, ignoring the user's colors")
  func rendersANSI() {
    let html = NFORenderer.html(
      for: Data("\u{1B}[1;31mhi\u{1B}[0m <".utf8), settings: PreviewSettings(colorMode: .light))
    #expect(html.contains("<span style=\"color:#ff5555;background:#000000\">hi</span> &lt;"))
    #expect(html.contains("background: #000000"))
    // A plain .ans takes the same path.
    #expect(
      NFORenderer.html(
        for: Data("x".utf8), pathExtension: "ans", settings: PreviewSettings(colorMode: .light)
      )
      .contains("background: #000000"))
  }

  @Test("embeds a font-face only when a bundled font file is given")
  func fontFace() {
    let data = Data("x".utf8)
    #expect(!NFORenderer.html(for: data, settings: PreviewSettings()).contains("@font-face"))
    let embedded = NFORenderer.html(
      for: data, settings: PreviewSettings(fontFamily: "Menlo"),
      font: (PreviewSettings.defaultFontFamily, Data("hi".utf8)))
    #expect(embedded.contains("src: url(\"data:font/ttf;base64,aGk=\")"))
    // A user pick must never be served a bundled file under its own name.
    #expect(embedded.contains("font-family: \"\(PreviewSettings.defaultFontFamily)\";"))
    #expect(embedded.contains("font-family: \"Menlo\","))
  }

  @Test("scales by the font's own cell height, and clamps a hand-edited scale")
  func fontSize() {
    func size(_ family: String, _ scale: Double) -> Int {
      NFORenderer.pixelSize(PreviewSettings(fontFamily: family, fontScale: scale))
    }
    #expect(size("Px437 IBM VGA 8x16", 1) == 16)
    #expect(size("Px437 IBM VGA 8x16", 2) == 32)
    #expect(size("Px437 IBM EGA 8x14", 1) == 14)
    #expect(size("Px437 IBM VGA 9x8", 4) == 32)
    // Shrinking rounds to a whole pixel: 14 × 0.25 = 3.5.
    #expect(size("Px437 IBM EGA 8x14", 0.25) == 4)
    // A system font carries no cell suffix, so it gets the VGA height.
    #expect(size("Menlo", 2) == 32)
    #expect(size("Px437 IBM VGA 8x16", 0) == 4)
    #expect(size("Px437 IBM VGA 8x16", 99) == 64)
  }

  @Test("steps through the scales and stops at either end")
  func scaleStepping() {
    #expect(PreviewSettings.fontScale(after: 1, steps: 1) == 2)
    #expect(PreviewSettings.fontScale(after: 1, steps: -1) == 0.5)
    #expect(PreviewSettings.fontScale(after: 4, steps: 1) == nil)
    #expect(PreviewSettings.fontScale(after: 0.25, steps: -1) == nil)
    // A hand-edited scale that is not on the ladder snaps back to 1×.
    #expect(PreviewSettings.fontScale(after: 3, steps: 1) == 1)
  }
}

@Suite("ANSI")
struct ANSITests {
  static func parse(_ art: String, columns: Int = 80, ice: Bool = false) -> [ANSI.Span] {
    ANSI.parse(
      Data(art.replacingOccurrences(of: "^", with: "\u{1B}").utf8), columns: columns, iceColors: ice
    )
  }

  static func text(_ spans: [ANSI.Span]) -> String {
    spans.map(\.text).joined()
  }

  @Test("detects .ans by extension and anything else by a CSI")
  func detection() {
    #expect(ANSI.isANSI(Data("plain".utf8), pathExtension: "ANS"))
    #expect(!ANSI.isANSI(Data("plain".utf8), pathExtension: "nfo"))
    #expect(ANSI.isANSI(Data("\u{1B}[0m".utf8), pathExtension: "diz"))
    #expect(!ANSI.isANSI(Data("\u{1B}".utf8), pathExtension: "nfo"))
  }

  @Test("cursor-forward skips cells, which read back as spaces")
  func cursorForward() {
    #expect(Self.text(Self.parse("^[3Cx^[Cy")) == "   x y")
  }

  @Test("a full-width line wraps, and the cursor-up that follows rejoins it — ACiD 50")
  func wrapAndCursorUp() {
    let full = String(repeating: "a", count: 4)
    #expect(Self.text(Self.parse("\(full)\r\n^[A^[2Cb", columns: 4)) == "aaaa\n  b")
  }

  @Test("positions, saves and restores the cursor, and clears the screen")
  func positioning() {
    #expect(Self.text(Self.parse("^[2;3Hx^[Hy")) == "y\n  x")
    #expect(Self.text(Self.parse("ab^[sxyz^[uQ")) == "abQyz")
    #expect(Self.text(Self.parse("gone^[2Jkept")) == "kept")
    // Moves past the top-left corner stop there.
    #expect(Self.text(Self.parse("^[5Dx^[99Ay")) == "xy")
  }

  @Test("colors: bold brightens, blink brightens the background only with iCE, 7 inverts")
  func colors() {
    let plain = Self.parse("^[1;31;44mx")
    #expect(plain == [.init(text: "x", foreground: 9, background: 4)])
    #expect(Self.parse("^[5;44mx")[0].background == 4)
    #expect(Self.parse("^[5;44mx", ice: true)[0].background == 12)
    #expect(
      Self.parse("^[7;32mx^[27my") == [
        .init(text: "x", foreground: 0, background: 2),
        .init(text: "y", foreground: 2, background: 0),
      ])
    #expect(Self.parse("^[1;33mx^[mz").last == .init(text: "z", foreground: 7, background: 0))
  }

  @Test("skips sequences it does not know, and decodes glyphs as CP437")
  func unknownAndGlyphs() {
    let spans = ANSI.parse(
      Data([0x1B, 0x5B, 0x3F, 0x37, 0x68, 0xDB, 0x1B, 0x5B, 0x4B, 0xB0, 0x1A, 0x41]), columns: 80,
      iceColors: false)
    #expect(Self.text(spans) == "█░")
  }

  @Test("drops trailing blanks, but not ones with a background")
  func trailingBlanks() {
    #expect(Self.text(Self.parse("x   \r\n\r\n")) == "x")
    #expect(Self.text(Self.parse("x^[41m  ")) == "x  ")
  }
}

@Suite("Round trip")
struct RoundTripTests {
  /// What `NFODocument` does on open and save. A file the user opened and
  /// saved without touching must come back byte for byte — SAUCE record, EOF
  /// marker and all.
  @Test(
    "decoding and re-encoding a file reproduces it exactly",
    arguments: [
      // DOS line endings, high glyphs, SAUCE record with a COMNT block
      Data([0xDA, 0xC4, 0xBF, 0x0D, 0x0A, 0xB3, 0xDB, 0xB3, 0x0D, 0x0A, 0xFE, 0xE1])
        + SauceTests.file(art: "", comments: ["hi"]),
      // Unix line endings, no trailer
      Data([0xB0, 0xB1, 0xB2, 0x0A, 0x41, 0x0A]),
    ])
  func fileRoundTrip(original: Data) {
    let (content, _) = SauceRecord.split(original)
    let trailer = original.dropFirst(content.count)
    var text = CP437.decode(content)
    if content.contains(0x0D) {
      text = text.replacingOccurrences(of: "\n", with: "\r\n")
    }
    #expect(CP437.encode(text) + trailer == original)
  }
}

@Suite("Bundled fonts")
struct BundledFontTests {
  @Test("every bundled family maps to a file that ships with the extension")
  func resourcesExist() throws {
    let directory = URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()  // NFOKitTests
      .deletingLastPathComponent()  // Tests
      .deletingLastPathComponent()  // repo root
      .appending(path: "Extension/Resources/Fonts")
    for family in PreviewSettings.bundledFontFamilies {
      let resource = try #require(PreviewSettings.bundledResource(for: family))
      let url = directory.appending(path: "\(resource).ttf")
      #expect(FileManager.default.fileExists(atPath: url.path), "missing \(url.lastPathComponent)")
    }
    #expect(PreviewSettings.bundledResource(for: "Menlo") == nil)
  }
}
