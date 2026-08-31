import AppKit
import NFOKit
import SwiftUI

@main
struct QuicklookNFOApp: App {
  var body: some Scene {
    // "Settings" is the HIG term since Ventura; "Preferences" is retired.
    Window("Quicklook NFO Settings", id: "settings") {
      PreferencesView()
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
    .windowResizability(.contentSize)
  }
}

struct PreferencesView: View {
  @State private var settings = PreviewSettings.load()
  /// Keyed by the settings key path — one identity per color well, for free.
  @FocusState private var focusedSwatch: WritableKeyPath<PreviewSettings, String>?

  /// Fixed-pitch families only — proportional fonts destroy ASCII art. A
  /// bundled family the user also installed system-wide is dropped here, so
  /// the picker never lists the same name in both groups.
  private static let monospaceFamilies: [String] = {
    let manager = NSFontManager.shared
    return manager.availableFontFamilies
      .filter { family in
        guard !PreviewSettings.bundledFontFamilies.contains(family),
          let font = NSFont(name: family, size: 12)
        else { return false }
        return font.isFixedPitch
      }
      .sorted()
  }()

  var body: some View {
    Form {
      Section {
        Picker("Font:", selection: $settings.fontFamily) {
          ForEach(PreviewSettings.bundledFontFamilies, id: \.self) { family in
            Text(family).tag(family)
          }
          Divider()
          ForEach(Self.monospaceFamilies, id: \.self) { family in
            Text(family).tag(family)
          }
        }

        // Whole multiples only — a pixel font at 1.5x is a blurry pixel font.
        Picker("Size:", selection: $settings.fontScale) {
          ForEach(PreviewSettings.fontScales, id: \.self) { scale in
            Text("\(scale)×").tag(scale)
          }
        }
        .pickerStyle(.segmented)

        // Only worth saying once the user has stepped off the bundled fonts.
        if PreviewSettings.bundledResource(for: settings.fontFamily) == nil {
          // Help text: the 11pt small system font, in the primary label color —
          // `.caption` is 10pt, below the smallest size the HIG asks for, and
          // grey is for de-emphasis, which a warning is not.
          Text("⚠️ \(settings.fontFamily) may not align perfectly for ASCII art.")
            .font(.subheadline)
        }
      }

      Section("Colors") {
        Picker("Appearance:", selection: $settings.colorMode) {
          Text("System").tag(PreviewSettings.ColorMode.system)
          Text("Light").tag(PreviewSettings.ColorMode.light)
          Text("Dark").tag(PreviewSettings.ColorMode.dark)
        }
        .pickerStyle(.segmented)

        // A pair per appearance, independently editable. Which one a preview
        // uses is the "Appearance" setting above.
        colorRow("Light:", text: \.lightForeground, background: \.lightBackground)
        colorRow("Dark:", text: \.darkForeground, background: \.darkBackground)
      }

      Section {
        HStack {
          Text("Restores the font, size and colors to their defaults.")
            .font(.subheadline)
          Spacer()
          // Assigning the defaults goes through onChange like any other edit.
          Button("Reset") { settings = PreviewSettings() }
            .disabled(settings == PreviewSettings())
        }
      } footer: {
        // A real `Link` rather than a markdown link inside `Text`: only a view
        // of its own can carry the hover cursor (and its own focus ring). The
        // price is that the pieces wrap separately, so the line is kept short
        // enough to fit the window's fixed 420pt width on one line.
        // Non-breaking spaces: SwiftUI trims leading/trailing whitespace off
        // each `Text`, so a plain space next to the link renders as nothing.
        HStack(spacing: 0) {
          Text("Fonts taken from\u{00A0}")
          Link(
            "Oldschool PC Fonts",
            destination: URL(string: "https://int10h.org/oldschool-pc-fonts/")!
          )
          // The container's `.secondary` would otherwise grey the link out.
          .foregroundStyle(Color(nsColor: .linkColor))
          .onHover { $0 ? NSCursor.pointingHand.push() : NSCursor.pop() }
          Text("\u{00A0}by VileR, licensed under CC-BY-SA.")
        }
        .lineLimit(1)
        .fixedSize()
        // Attribution stays de-emphasised — the one place grey is right.
        .font(.subheadline)
        .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .onChange(of: settings) { _, new in new.save() }
  }

  /// Both wells on a single line, so the pair reads as one setting.
  private func colorRow(
    _ title: String,
    text: WritableKeyPath<PreviewSettings, String>,
    background: WritableKeyPath<PreviewSettings, String>
  ) -> some View {
    // Two rows now carry a "Text" well, so the row name goes into the
    // accessibility label or VoiceOver reads them as the same control.
    let appearance = title.replacingOccurrences(of: ":", with: "")
    return LabeledContent(title) {
      HStack(spacing: 16) {
        swatch(text, label: "Text", accessibility: "\(appearance) text color")
        swatch(background, label: "Background", accessibility: "\(appearance) background color")
        Spacer()
      }
      .fixedSize()
    }
  }

  /// The label sits outside the `ColorPicker` so the focus ring can hug the
  /// well itself — AppKit's minimal color well draws no ring of its own.
  private func swatch(
    _ path: WritableKeyPath<PreviewSettings, String>, label: String, accessibility: String
  ) -> some View {
    HStack(spacing: 6) {
      Text(label)
      ColorPicker("", selection: hexBinding(path), supportsOpacity: false)
        .labelsHidden()
        .accessibilityLabel(accessibility)
        // No `.focusable()`: the color well is already a tab stop of its own,
        // and adding one would put two stops on the same swatch.
        .focused($focusedSwatch, equals: path)
        .overlay {
          RoundedRectangle(cornerRadius: 5)
            .strokeBorder(Color.accentColor, lineWidth: 3)
            .padding(-2)
            .opacity(focusedSwatch == path ? 1 : 0)
        }
    }
  }

  /// `ColorPicker` speaks `Color`, `PreviewSettings` stores `#rrggbb` for CSS.
  private func hexBinding(_ path: WritableKeyPath<PreviewSettings, String>) -> Binding<Color> {
    Binding(
      get: { Color(hex: settings[keyPath: path]) },
      set: { settings[keyPath: path] = $0.hex }
    )
  }
}

extension Color {
  fileprivate init(hex: String) {
    let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
    self.init(
      .sRGB,
      red: Double((value >> 16) & 0xFF) / 255,
      green: Double((value >> 8) & 0xFF) / 255,
      blue: Double(value & 0xFF) / 255
    )
  }

  fileprivate var hex: String {
    guard let rgb = NSColor(self).usingColorSpace(.sRGB) else {
      return PreviewSettings.defaultLightForeground
    }
    let channel = { (value: CGFloat) in Int((value * 255).rounded()) }
    return String(
      format: "#%02x%02x%02x", channel(rgb.redComponent), channel(rgb.greenComponent),
      channel(rgb.blueComponent))
  }
}
