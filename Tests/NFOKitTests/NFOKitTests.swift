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
    func size(_ family: String, _ scale: Int) -> Int {
      NFORenderer.pixelSize(PreviewSettings(fontFamily: family, fontScale: scale))
    }
    #expect(size("Px437 IBM VGA 8x16", 1) == 16)
    #expect(size("Px437 IBM VGA 8x16", 2) == 32)
    #expect(size("Px437 IBM EGA 8x14", 1) == 14)
    #expect(size("Px437 IBM VGA 9x8", 3) == 24)
    // A system font carries no cell suffix, so it gets the VGA height.
    #expect(size("Menlo", 2) == 32)
    #expect(size("Px437 IBM VGA 8x16", 0) == 16)
    #expect(size("Px437 IBM VGA 8x16", 99) == 48)
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
