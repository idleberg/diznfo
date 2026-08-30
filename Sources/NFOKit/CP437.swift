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
