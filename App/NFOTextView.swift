import AppKit
import NFOKit
import SwiftUI

/// The document view: one `NSTextView` for both reading and editing, so the
/// art never reflows or re-renders when the lock is flipped.
struct NFOTextView: NSViewRepresentable {
  @Binding var text: String
  let columns: Int
  let settings: PreviewSettings
  let isEditable: Bool

  func makeNSView(context: Context) -> NSScrollView {
    let textView = ColumnGuideTextView()
    // Drops the view to TextKit 1. TextKit 2 draws the caret in a private
    // insertion-indicator view and never calls `drawInsertionPoint`, so the
    // block cursor below would silently never run. Nothing here needs TextKit
    // 2: the text is one font, one color, no attachments.
    _ = textView.layoutManager
    textView.delegate = context.coordinator
    textView.isRichText = false
    textView.allowsUndo = true
    textView.usesFindBar = true
    textView.isIncrementalSearchingEnabled = true
    // Every "helpful" substitution mangles ASCII art.
    textView.isAutomaticQuoteSubstitutionEnabled = false
    textView.isAutomaticDashSubstitutionEnabled = false
    textView.isAutomaticTextReplacementEnabled = false
    textView.isAutomaticSpellingCorrectionEnabled = false
    textView.isContinuousSpellCheckingEnabled = false
    textView.isGrammarCheckingEnabled = false

    // Art is wider than the window as often as not, so lines never wrap and
    // the view grows horizontally instead.
    textView.isHorizontallyResizable = true
    let unbounded = NSSize(
      width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
    textView.maxSize = unbounded
    textView.textContainer?.widthTracksTextView = false
    textView.textContainer?.size = unbounded
    // The guide is measured from the text's own origin; AppKit's default 5pt
    // of container padding would put it five points off.
    textView.textContainer?.lineFragmentPadding = 0

    let scrollView = NSScrollView()
    scrollView.documentView = textView
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = true
    scrollView.autohidesScrollers = true
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    guard let textView = scrollView.documentView as? ColumnGuideTextView else { return }
    context.coordinator.text = $text

    if textView.string != text {
      textView.string = text
    }

    let font = Self.font(for: settings)
    let palette = NFORenderer.Palette.resolve(
      settings, isDarkAppearance: textView.effectiveAppearance.isDark)
    let foreground = NSColor(hex: palette.foreground)

    // The HTML preview sets `line-height: 1.0`; the equivalent here is a line
    // box exactly as tall as the font's design height.
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = 0
    paragraph.minimumLineHeight = font.pointSize
    paragraph.maximumLineHeight = font.pointSize

    textView.typingAttributes = [
      .font: font, .foregroundColor: foreground, .paragraphStyle: paragraph,
    ]
    textView.textStorage?.setAttributes(
      textView.typingAttributes, range: NSRange(location: 0, length: textView.string.utf16.count))

    let background = NSColor(hex: palette.background)
    textView.textColor = foreground
    textView.backgroundColor = background
    // The text view is only as wide as the art; without this the window shows
    // system grey either side of it.
    scrollView.backgroundColor = background
    // Only reached if AppKit draws the caret itself rather than calling
    // `drawInsertionPoint` — the foreground at least beats the system blue.
    textView.insertionPointColor = foreground
    textView.selectedTextAttributes = [
      .backgroundColor: foreground.withAlphaComponent(0.3)
    ]
    // `padding: 1em` in the preview.
    textView.textContainerInset = NSSize(width: font.pointSize, height: font.pointSize)

    textView.isEditable = isEditable
    // The guide only means something while typing, and it would otherwise read
    // as part of the artwork.
    textView.guideColumns = isEditable ? columns : nil
    textView.needsDisplay = true
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(text: $text)
  }

  /// A bundled family resolves through the font manager; a system pick the
  /// user made in Settings may since have been uninstalled, hence the fallback.
  private static func font(for settings: PreviewSettings) -> NSFont {
    let size = CGFloat(NFORenderer.pixelSize(settings))
    return NSFontManager.shared.font(
      withFamily: settings.fontFamily, traits: [], weight: 5, size: size)
      ?? NSFont(name: settings.fontFamily, size: size)
      ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
  }

  final class Coordinator: NSObject, NSTextViewDelegate {
    var text: Binding<String>

    init(text: Binding<String>) {
      self.text = text
    }

    func textDidChange(_ notification: Notification) {
      guard let textView = notification.object as? NSTextView else { return }
      text.wrappedValue = textView.string
    }
  }
}

/// Shades everything past the column the art was drawn for, so overrunning the
/// standard width while editing is visible rather than a surprise in QuickLook.
final class ColumnGuideTextView: NSTextView {
  /// `nil` while locked — no guide when nothing can be typed.
  var guideColumns: Int?

  /// The art is one color on one background, so a caret in either color is
  /// invisible on half the artwork. This is the DOS block cursor: the cell is
  /// filled with the foreground and the character in it redrawn in the
  /// background, so the cell is inverted whatever it holds.
  ///
  /// A `.difference` blend would say the same thing in one line, but AppKit
  /// composites the caret apart from the text, so it only ever inverts the
  /// background it is drawn onto — never the glyph.
  override func drawInsertionPoint(in rect: NSRect, color: NSColor, turnedOn flag: Bool) {
    // A whole character cell wide, so it reads as a block rather than a
    // hairline in an 8-pixel cell.
    var caret = rect
    caret.size.width = cellWidth ?? rect.width

    guard flag else {
      // The off half of the blink: super invalidates the rect so the glyph
      // underneath is redrawn intact.
      super.drawInsertionPoint(in: caret, color: color, turnedOn: flag)
      return
    }

    let foreground = textColor ?? color
    foreground.setFill()
    caret.fill()

    // The character the caret sits on, in the background color — the other
    // half of the inversion. Nothing to redraw at the end of a line.
    let location = selectedRange().location
    guard location < string.utf16.count else { return }
    let character = (string as NSString).substring(
      with: NSRange(location: location, length: 1))
    guard !character.hasPrefix("\n") else { return }

    var attributes = typingAttributes
    attributes[.foregroundColor] = backgroundColor
    NSAttributedString(string: character, attributes: attributes).draw(at: caret.origin)
  }

  /// One character cell. The art is monospaced by definition, so a space
  /// measures every cell.
  private var cellWidth: CGFloat? {
    font.map { $0.advancement(forGlyph: $0.glyph(withName: "space")).width }
  }

  override func drawBackground(in rect: NSRect) {
    super.drawBackground(in: rect)
    guard let columns = guideColumns, let advance = cellWidth else { return }

    let start = textContainerInset.width + advance * CGFloat(columns)
    guard advance > 0, rect.maxX > start else { return }

    // 20% toward black, as asked — except on an already-black background,
    // where 20% of nothing is nothing, so it goes the other way.
    let background = backgroundColor.usingColorSpace(.sRGB) ?? backgroundColor
    let shade = background.brightnessComponent < 0.2 ? NSColor.white : NSColor.black
    background.blended(withFraction: 0.2, of: shade)?.setFill()
    NSRect(x: start, y: rect.minY, width: rect.maxX - start, height: rect.height).fill()
  }
}

extension NSAppearance {
  var isDark: Bool { bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
}
