import NFOKit
import SwiftUI
import UniformTypeIdentifiers

extension UTType {
  /// Declared by the app in `UTExportedTypeDeclarations` — see project.yml.
  static let nfo = UTType(exportedAs: "com.idleberg.Diznfo.nfo")
  static let diz = UTType(exportedAs: "com.idleberg.Diznfo.diz")
  static let ans = UTType(exportedAs: "com.idleberg.Diznfo.ans")
}

/// An open `.nfo` / `.diz` / `.ans` file — see `NFOFile` for what is kept.
struct NFODocument: FileDocument {
  static let readableContentTypes: [UTType] = [.nfo, .diz, .ans]

  /// For ANSI art only its plain text, for find and copy.
  var text: String
  private let file: NFOFile

  init(configuration: ReadConfiguration) throws {
    guard let data = configuration.file.regularFileContents else {
      throw CocoaError(.fileReadCorruptFile)
    }
    file = NFOFile(
      data: data, pathExtension: configuration.contentType.preferredFilenameExtension ?? "")
    text = file.text
  }

  /// Set for ANSI art, which is read-only.
  var ansiSpans: [ANSI.Span]? {
    guard case .ansi(let spans) = file.content else { return nil }
    return spans
  }

  var columns: Int { file.columns }

  func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
    FileWrapper(regularFileWithContents: file.data(text: text))
  }
}
