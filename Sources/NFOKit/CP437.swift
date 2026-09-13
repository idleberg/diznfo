import Foundation

/// Code page 437 (IBM PC / DOS) byte → Unicode decoding.
///
/// `String.Encoding` has no CP437, so this is a plain 256-entry table.
/// Bytes 0x00–0x1F map to the *graphic* glyphs DOS drew for them (☺, ♠, ►, …),
/// which is what ASCII art relies on — except tab, LF and CR, which stay
/// control characters so line handling still works.
public enum CP437 {
  // swiftlint:disable line_length
  private static let table: [Character] = Array(
    " ☺☻♥♦♣♠•◘○◙♂♀♪♫☼►◄↕‼¶§▬↨↑↓→←∟↔▲▼ !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~⌂ÇüéâäàåçêëèïîìÄÅÉæÆôöòûùÿÖÜ¢£¥₧ƒáíóúñÑªº¿⌐¬½¼¡«»░▒▓│┤╡╢╖╕╣║╗╝╜╛┐└┴┬├─┼╞╟╚╔╩╦╠═╬╧╨╤╥╙╘╒╓╫╪┘┌█▄▌▐▀αßΓπΣσµτΦΘΩδ∞φε∩≡±≥≤⌠⌡÷≈°∙·√ⁿ²■\u{00A0}"
  )
  // swiftlint:enable line_length

  /// Reverse of `table`. Several bytes draw the same glyph (0x00 and 0x20 are
  /// both a space), so later entries win — the plain ASCII byte is always the
  /// higher one, which is the one worth writing back.
  ///
  /// Keyed by scalar rather than `Character`: Swift folds CRLF into a single
  /// `Character`, which would encode a DOS line ending as one `?`.
  private static let reverse: [Unicode.Scalar: UInt8] = {
    var map: [Unicode.Scalar: UInt8] = [:]
    for byte in 0...255 { map[table[byte].unicodeScalars.first!] = UInt8(byte) }
    // Restore the three the decoder keeps as control characters.
    map["\t"] = 0x09
    map["\n"] = 0x0A
    map["\r"] = 0x0D
    return map
  }()

  /// Encodes back to CP437. Characters with no CP437 glyph become `?` — the
  /// same substitution DOS itself made. Line endings are the caller's call:
  /// whatever is in the string is what gets written.
  public static func encode(_ text: String) -> Data {
    Data(text.unicodeScalars.map { reverse[$0] ?? 0x3F })
  }

  /// Decodes CP437 bytes and normalizes DOS line endings (CRLF / lone CR → LF).
  public static func decode(_ bytes: some Sequence<UInt8>) -> String {
    var out = ""
    for byte in bytes {
      switch byte {
      case 0x09, 0x0A, 0x0D: out.append(Character(UnicodeScalar(byte)))
      default: out.append(table[Int(byte)])
      }
    }
    return
      out
      .replacingOccurrences(of: "\r\n", with: "\n")
      .replacingOccurrences(of: "\r", with: "\n")
  }
}
