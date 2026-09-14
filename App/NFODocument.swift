import NFOKit
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
  /// Declared by the app in `UTExportedTypeDeclarations` — see project.yml.
  static let nfo = UTType(exportedAs: "com.idleberg.Diznfo.nfo")
  static let diz = UTType(exportedAs: "com.idleberg.Diznfo.diz")
  static let ans = UTType(exportedAs: "com.idleberg.Diznfo.ans")
}

/// An open `.nfo` / `.diz` / `.ans` file.
///
/// Everything that is not art — the DOS EOF marker, a COMNT block, the SAUCE
/// record — is kept as opaque bytes and written back untouched, so opening and
/// saving a file without editing it reproduces the original byte for byte.
struct NFODocument: FileDocument {
  static let readableContentTypes: [UTType] = [.nfo, .diz, .ans]

  var text: String
  /// Set for ANSI art, which is read-only: `text` is then only its plain
  /// text, for find and copy, and the whole file is written back as it came.
  let ansiSpans: [ANSI.Span]?
  /// The bytes after the art: EOF marker, COMNT block and SAUCE record — or
  /// the whole file, for ANSI art.
  private var trailer: Data
  /// DOS files are CRLF; a file that arrived with LF is written back with LF.
  private var usesCRLF: Bool
  /// The width the art was drawn for. SAUCE when it says so, else the
  /// standard 80 — the same precedence the QuickLook extension uses.
  let columns: Int

  init(configuration: ReadConfiguration) throws {
    guard let data = configuration.file.regularFileContents else {
      throw CocoaError(.fileReadCorruptFile)
    }
    let (content, sauce) = SauceRecord.split(data)
    columns = sauce?.width ?? NFORenderer.defaultColumns
    usesCRLF = content.contains(0x0D)

    let pathExtension = configuration.contentType.preferredFilenameExtension ?? ""
    if ANSI.isANSI(content, pathExtension: pathExtension) {
      let spans = ANSI.parse(
        content, columns: columns, iceColors: sauce?.usesICEColors ?? false)
      ansiSpans = spans
      text = spans.map(\.text).joined()
      trailer = data
    } else {
      ansiSpans = nil
      text = CP437.decode(content)
      // `split` returns a prefix, so whatever follows it is the trailer.
      trailer = data.dropFirst(content.count)
    }
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    if ansiSpans != nil {
      return FileWrapper(regularFileWithContents: trailer)
    }
    let art = usesCRLF ? text.replacingOccurrences(of: "\n", with: "\r\n") : text
    return FileWrapper(regularFileWithContents: CP437.encode(art) + trailer)
  }
}
