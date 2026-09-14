import Foundation

/// ANSI art (`.ans`, and `.nfo`/`.diz` carrying escape codes): CP437 bytes
/// interleaved with ANSI.SYS escape sequences that set colors and move the
/// cursor.
///
/// The sequences handled are libansilove's — what 16colo.rs renders with:
/// <https://github.com/ansilove/libansilove/blob/master/src/loaders/ansi.c>
/// — plus xterm's bright, 256-color and truecolor codes, which UTF-8 art
/// made in modern terminals relies on.
public enum ANSI {
  /// A stretch of decoded text in one color pair. Newlines are part of the
  /// text, so the spans concatenated are the plain text of the art.
  public struct Span: Equatable, Sendable {
    public var text: String
    public var foreground: Color
    public var background: Color
  }

  public enum Color: Equatable, Sendable {
    /// 0–15 the VGA palette, then xterm's 6×6×6 cube and grey ramp. Resolving
    /// indexes is the output's job — see `color` — so a different palette is
    /// only a different table.
    case palette(UInt8)
    case rgb(UInt8, UInt8, UInt8)
  }

  /// A color as `#rrggbb`.
  public static func color(_ color: Color) -> String {
    func hex(_ red: Int, _ green: Int, _ blue: Int) -> String {
      String(format: "#%02x%02x%02x", red, green, blue)
    }
    switch color {
    case .rgb(let red, let green, let blue):
      return hex(Int(red), Int(green), Int(blue))
    case .palette(let index) where index < 16:
      return vga[Int(index)]
    case .palette(let index) where index < 232:
      let levels = [0, 95, 135, 175, 215, 255]
      let cube = Int(index) - 16
      return hex(levels[cube / 36], levels[cube / 6 % 6], levels[cube % 6])
    case .palette(let index):
      let grey = 8 + 10 * (Int(index) - 232)
      return hex(grey, grey, grey)
    }
  }

  /// The IBM VGA text-mode palette, in ANSI order (black, red, green, brown,
  /// blue, magenta, cyan, grey), then the bright eight.
  private static let vga = [
    "#000000", "#aa0000", "#00aa00", "#aa5500", "#0000aa", "#aa00aa", "#00aaaa", "#aaaaaa",
    "#555555", "#ff5555", "#55ff55", "#ffff55", "#5555ff", "#ff55ff", "#55ffff", "#ffffff",
  ]
  public static let defaultForeground = Color.palette(7)
  public static let defaultBackground = Color.palette(0)

  /// `.ans` always is; an `.nfo`/`.diz` is when it contains a CSI (`ESC [`).
  /// Plain text art never contains ESC, so it keeps its own rendering path.
  public static func isANSI(_ content: Data, pathExtension: String) -> Bool {
    pathExtension.lowercased() == "ans"
      || zip(content, content.dropFirst()).contains { $0 == 0x1B && $1 == 0x5B }
  }

  private struct Cell {
    var glyph: Character = " "
    var foreground = defaultForeground
    var background = defaultBackground
  }

  /// Plays the art onto a `columns`-wide screen and reads it back as spans.
  ///
  /// - Parameters:
  ///   - content: the art without its SAUCE trailer — see `SauceRecord.split`.
  ///   - iceColors: SAUCE's iCE flag. Blink (SGR 5) then brightens the
  ///     background instead; without it blink is dropped, as nothing animates.
  ///   - isUTF8: glyphs are UTF-8 rather than CP437 — see `NFOFile`.
  // One flat switch per escape code reads better than the same cases spread
  // over helpers passing the cursor state around.
  // swiftlint:disable:next cyclomatic_complexity function_body_length
  public static func parse(
    _ content: Data, columns: Int, iceColors: Bool, isUTF8: Bool = false
  ) -> [Span] {
    let bytes = [UInt8](content)
    let columns = max(1, columns)
    var screen: [[Cell]] = []
    var row = 0
    var column = 0
    var saved = (row: 0, column: 0)
    var foreground = defaultForeground
    var background = defaultBackground
    var bold = false
    var blink = false
    var inverse = false

    // Bold and iCE blink brighten the eight basic colors and nothing richer.
    func brightened(_ color: Color, _ isOn: Bool) -> Color {
      guard isOn, case .palette(let index) = color, index < 8 else { return color }
      return .palette(index + 8)
    }

    func put(_ glyph: Character) {
      while screen.count <= row { screen.append([]) }
      while screen[row].count <= column { screen[row].append(Cell()) }
      let fg = brightened(foreground, bold)
      let bg = brightened(background, blink && iceColors)
      var cell = Cell(glyph: glyph, foreground: fg, background: bg)
      if inverse {
        // libansilove's inversion rather than a plain swap: the background
        // loses its brightness, the foreground keeps its own. `|` where it
        // has `+`, which would run off the palette for bold on an iCE
        // background. Colors beyond the sixteen just swap.
        if case .palette(let fgIndex) = fg, case .palette(let bgIndex) = bg, fgIndex < 16,
          bgIndex < 16
        {
          cell.foreground = .palette(bgIndex | (fgIndex & 8))
          cell.background = .palette(fgIndex % 8)
        } else {
          (cell.foreground, cell.background) = (bg, fg)
        }
      }
      screen[row][column] = cell
      column += 1
    }

    var index = 0
    scan: while index < bytes.count {
      // Wraps before reading the next byte, whatever it is, so the CR/LF
      // after a full-width line lands one row further down — which is why
      // such art follows it with a cursor-up. A cursor moved to the edge
      // wraps the same way.
      if column == columns {
        row += 1
        column = 0
      }
      let byte = bytes[index]
      index += 1
      switch byte {
      case 0x1A:
        break scan
      case 0x0D:
        // libansilove ignores CR; ANSI.SYS returned to column 0. Only a lone
        // CR tells the two apart, and there DOS is what the artist saw.
        column = 0
      case 0x0A:
        row += 1
        column = 0
      case 0x09:
        // Tab stops every 8 columns, as ANSI.SYS had; libansilove just adds 8.
        column = min((column / 8 + 1) * 8, columns)
      case 0x1B where index < bytes.count && bytes[index] == 0x5B:
        // CSI: parameter bytes up to a final byte in 0x40–0x7E.
        var end = index + 1
        while end < bytes.count, !(0x40...0x7E).contains(bytes[end]) { end += 1 }
        guard end < bytes.count else { break scan }
        let parameters = String(decoding: bytes[(index + 1)..<end], as: UTF8.self)
          .split(separator: ";", omittingEmptySubsequences: false)
          .map { Int($0) }
        index = end + 1
        // A missing or zero count means one.
        func count(_ position: Int = 0) -> Int {
          let value = parameters.indices.contains(position) ? parameters[position] ?? 0 : 0
          return max(1, value)
        }

        switch bytes[end] {
        case UInt8(ascii: "A"): row = max(0, row - count())
        case UInt8(ascii: "B"): row += count()
        case UInt8(ascii: "C"): column = min(columns, column + count())
        case UInt8(ascii: "D"): column = max(0, column - count())
        case UInt8(ascii: "H"), UInt8(ascii: "f"):
          row = count(0) - 1
          column = min(columns - 1, count(1) - 1)
        case UInt8(ascii: "s"): saved = (row, column)
        case UInt8(ascii: "u"): (row, column) = saved
        case UInt8(ascii: "J") where parameters.first == 2:
          screen = []
          row = 0
          column = 0
        case UInt8(ascii: "m"):
          let values = parameters.map { $0 ?? 0 }
          var next = 0
          while next < values.count {
            let parameter = values[next]
            next += 1
            switch parameter {
            case 0:
              foreground = defaultForeground
              background = defaultBackground
              bold = false
              blink = false
              inverse = false
            case 1: bold = true
            case 22: bold = false
            case 5: blink = true
            case 25: blink = false
            case 7: inverse = true
            case 27: inverse = false
            case 30...37: foreground = .palette(UInt8(parameter - 30))
            case 39: foreground = defaultForeground
            case 40...47: background = .palette(UInt8(parameter - 40))
            case 49: background = defaultBackground
            case 90...97: foreground = .palette(UInt8(parameter - 90 + 8))
            case 100...107: background = .palette(UInt8(parameter - 100 + 8))
            case 38, 48:
              // `5;n` picks from 256 colors, `2;r;g;b` is truecolor. Their
              // arguments are consumed either way, so they are never misread
              // as codes of their own.
              let arguments = values[next...].map { UInt8(clamping: $0) }
              let color: Color?
              switch arguments.first {
              case 5 where arguments.count >= 2:
                color = .palette(arguments[1])
                next += 2
              case 2 where arguments.count >= 4:
                color = .rgb(arguments[1], arguments[2], arguments[3])
                next += 4
              default:
                color = nil
                next = values.count
              }
              if let color {
                if parameter == 38 { foreground = color } else { background = color }
              }
            default: break
            }
          }
        default:
          break  // K, and anything else ANSI.SYS art does not rely on.
        }
      case 0x80... where isUTF8:
        // The lead byte says how long the sequence is; `NFOFile` has already
        // checked the whole file decodes.
        let length = byte >= 0xF0 ? 4 : byte >= 0xE0 ? 3 : 2
        let end = min(index - 1 + length, bytes.count)
        put(String(decoding: bytes[(index - 1)..<end], as: UTF8.self).first ?? "\u{FFFD}")
        index = end
      default:
        put(CP437.glyph(byte))
      }
    }

    return spans(from: screen)
  }

  /// Rows joined by newlines, adjacent cells of one color pair merged.
  /// Trailing blanks on the default background are dropped — they draw
  /// nothing, and would pad every line out to the full width.
  private static func spans(from screen: [[Cell]]) -> [Span] {
    func isBlank(_ cell: Cell) -> Bool {
      cell.glyph == " " && cell.background == defaultBackground
    }
    var rows = screen.map { row in
      Array(row[..<(row.lastIndex { !isBlank($0) }.map { $0 + 1 } ?? 0)])
    }
    while rows.last?.isEmpty == true { rows.removeLast() }

    var spans: [Span] = []
    func append(_ glyph: Character, foreground: Color, background: Color) {
      if let last = spans.last, last.foreground == foreground, last.background == background {
        spans[spans.count - 1].text.append(glyph)
      } else {
        spans.append(Span(text: String(glyph), foreground: foreground, background: background))
      }
    }
    for (number, row) in rows.enumerated() {
      // On the default background: NSTextView paints a colored newline's
      // background out to the edge of the view.
      if number > 0 {
        append("\n", foreground: defaultForeground, background: defaultBackground)
      }
      for cell in row {
        append(cell.glyph, foreground: cell.foreground, background: cell.background)
      }
    }
    return spans
  }
}
