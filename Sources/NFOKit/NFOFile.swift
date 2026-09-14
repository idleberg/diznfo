import Foundation

/// An opened `.nfo` / `.diz` / `.ans` file. The app and the QuickLook preview
/// both open files through this, so they cannot disagree about which files
/// are ANSI art or what width they were drawn for.
///
/// Everything that is not art — the DOS EOF marker, a COMNT block, the SAUCE
/// record — is kept as opaque bytes and written back untouched, so opening and
/// saving a file without editing it reproduces the original byte for byte.
public struct NFOFile: Sendable {
  public enum Content: Equatable, Sendable {
    case text(String)
    /// Read-only: escape codes are not text, so there is nothing to edit.
    case ansi([ANSI.Span])
  }

  public let content: Content
  /// The width the art was drawn for: SAUCE when it says so, else the
  /// standard 80.
  public let columns: Int
  /// The bytes written back around the art: EOF marker, COMNT block and SAUCE
  /// record after it — or the whole file, for ANSI art.
  private let preserved: Data
  /// DOS files are CRLF; a file that arrived with LF is written back with LF.
  private let usesCRLF: Bool
  /// Art is CP437 unless it is UTF-8 — and saved in whichever it was.
  private let isUTF8: Bool
  private let hasBOM: Bool

  private static let bom = Data([0xEF, 0xBB, 0xBF])

  /// - Parameter pathExtension: `.ans` is ANSI art even without a single
  ///   escape code. See `ANSI.isANSI`.
  public init(data: Data, pathExtension: String) {
    let (art, sauce) = SauceRecord.split(data)
    columns = sauce?.width ?? NFORenderer.defaultColumns
    usesCRLF = art.contains(0x0D)
    hasBOM = art.starts(with: Self.bom)
    let body = hasBOM ? art.dropFirst(Self.bom.count) : art
    // Any bytes at all are valid CP437, so UTF-8 has to prove itself: a BOM,
    // or a whole file that decodes and is not plain ASCII. CP437 art almost
    // never decodes by accident.
    isUTF8 = hasBOM || (body.contains { $0 >= 0x80 } && String(data: body, encoding: .utf8) != nil)

    if ANSI.isANSI(body, pathExtension: pathExtension) {
      content = .ansi(
        ANSI.parse(
          body, columns: columns, iceColors: sauce?.usesICEColors ?? false, isUTF8: isUTF8))
      preserved = data
    } else {
      content = .text(
        isUTF8
          ? String(decoding: body, as: UTF8.self)
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
          : CP437.decode(body))
      // `split` returns a prefix, so whatever follows it is not art.
      preserved = data.dropFirst(art.count)
    }
  }

  /// The art as plain text — for ANSI art, only its characters.
  public var text: String {
    switch content {
    case .text(let text): text
    case .ansi(let spans): spans.map(\.text).joined()
    }
  }

  /// The file with `text` as its art. ANSI art ignores `text` and comes back
  /// exactly as it was read.
  public func data(text: String) -> Data {
    guard case .text = content else { return preserved }
    let art = usesCRLF ? text.replacingOccurrences(of: "\n", with: "\r\n") : text
    guard isUTF8 else { return CP437.encode(art) + preserved }
    return (hasBOM ? Self.bom : Data()) + Data(art.utf8) + preserved
  }
}
