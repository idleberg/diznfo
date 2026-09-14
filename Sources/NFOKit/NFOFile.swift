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

  /// - Parameter pathExtension: `.ans` is ANSI art even without a single
  ///   escape code. See `ANSI.isANSI`.
  public init(data: Data, pathExtension: String) {
    let (art, sauce) = SauceRecord.split(data)
    columns = sauce?.width ?? NFORenderer.defaultColumns
    usesCRLF = art.contains(0x0D)
    if ANSI.isANSI(art, pathExtension: pathExtension) {
      content = .ansi(
        ANSI.parse(art, columns: columns, iceColors: sauce?.usesICEColors ?? false))
      preserved = data
    } else {
      content = .text(CP437.decode(art))
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
    return CP437.encode(art) + preserved
  }
}
