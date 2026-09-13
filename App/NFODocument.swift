import NFOKit
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
  /// Declared by the app in `UTExportedTypeDeclarations` — see project.yml.
  static let nfo = UTType(exportedAs: "com.idleberg.Diznfo.nfo")
  static let diz = UTType(exportedAs: "com.idleberg.Diznfo.diz")
}

/// An open `.nfo` / `.diz` file.
///
/// Everything that is not art — the DOS EOF marker, a COMNT block, the SAUCE
/// record — is kept as opaque bytes and written back untouched, so opening and
/// saving a file without editing it reproduces the original byte for byte.
struct NFODocument: FileDocument {
  static let readableContentTypes: [UTType] = [.nfo, .diz]

  var text: String
  /// The bytes after the art: EOF marker, COMNT block and SAUCE record.
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
    text = CP437.decode(content)
    // `split` returns a prefix, so whatever follows it is the trailer.
    trailer = data.dropFirst(content.count)
    usesCRLF = content.contains(0x0D)
    columns = sauce?.width ?? NFORenderer.defaultColumns
  }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    let art = usesCRLF ? text.replacingOccurrences(of: "\n", with: "\r\n") : text
    return FileWrapper(regularFileWithContents: CP437.encode(art) + trailer)
  }
}
