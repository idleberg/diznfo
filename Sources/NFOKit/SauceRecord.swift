import Foundation

/// A SAUCE v00 metadata record — the fixed 128-byte trailer scene releases
/// append to `.nfo`/`.ans` files. Spec: <https://www.acid.org/info/sauce/sauce.htm>
public struct SauceRecord: Equatable, Sendable {
  public var title: String
  public var author: String
  public var group: String
  public var date: String  // CCYYMMDD, as written
  public var dataType: UInt8
  public var fileType: UInt8
  public var tInfo1: UInt16
  public var tInfo2: UInt16
  public var flags: UInt8
  public var fontName: String

  /// Intended column count, but only for character-based files (DataType 1).
  /// `nil` means "no usable hint" — caller falls back to its own default.
  public var width: Int? {
    guard dataType == 1, tInfo1 > 0 else { return nil }
    return Int(tInfo1)
  }

  /// iCE colors bit (ANSiFlags bit 0). Parsed now, only meaningful once
  /// `.ans` rendering lands.
  public var usesICEColors: Bool { flags & 0b1 != 0 }

  public static let size = 128
  private static let signature = Data("SAUCE00".utf8)
  private static let commentID = Data("COMNT".utf8)
  private static let commentLineSize = 64

  /// Splits a file into its art content and its SAUCE record (if any).
  ///
  /// Strips the SAUCE trailer, any COMNT block ahead of it, and the DOS EOF
  /// marker (0x1A) so the art can be decoded on its own.
  public static func split(_ data: Data) -> (content: Data, sauce: SauceRecord?) {
    guard data.count >= size,
      data.suffix(size).prefix(signature.count).elementsEqual(signature),
      let record = SauceRecord(record: data.suffix(size))
    else {
      return (stripEOF(data), nil)
    }

    var contentEnd = data.count - size
    let commentCount = Int(data[data.index(data.startIndex, offsetBy: contentEnd + 104)])
    if commentCount > 0 {
      let blockSize = commentID.count + commentCount * commentLineSize
      let blockStart = contentEnd - blockSize
      if blockStart >= 0,
        data[data.startIndex + blockStart..<data.startIndex + blockStart + commentID.count]
          .elementsEqual(commentID)
      {
        contentEnd = blockStart
      }
    }
    return (stripEOF(data.prefix(contentEnd)), record)
  }

  private static func stripEOF(_ data: Data) -> Data {
    var end = data.endIndex
    while end > data.startIndex, data[data.index(before: end)] == 0x1A {
      end = data.index(before: end)
    }
    return Data(data[data.startIndex..<end])
  }

  /// Parses the 128 record bytes themselves. Returns `nil` unless it is a
  /// well-formed `SAUCE00` record.
  init?(record: Data) {
    let bytes = [UInt8](record)
    guard bytes.count == Self.size, bytes.prefix(7).elementsEqual(Self.signature) else {
      return nil
    }
    func text(_ range: Range<Int>) -> String {
      CP437.decode(bytes[range]).trimmingCharacters(in: .whitespacesAndNewlines)
    }
    func word(_ offset: Int) -> UInt16 {
      UInt16(bytes[offset]) | UInt16(bytes[offset + 1]) << 8
    }
    title = text(7..<42)
    author = text(42..<62)
    group = text(62..<82)
    date = text(82..<90)
    dataType = bytes[94]
    fileType = bytes[95]
    tInfo1 = word(96)
    tInfo2 = word(98)
    flags = bytes[105]
    fontName = text(106..<128).replacingOccurrences(of: "\0", with: "")
  }
}
