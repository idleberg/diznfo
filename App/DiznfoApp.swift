import AppKit
import NFOKit
import SwiftUI

@main
struct DiznfoApp: App {
  @State private var store = SettingsStore()

  var body: some Scene {
    DocumentGroup(viewing: NFODocument.self) { file in
      NFODocumentView(document: file.$document)
        .environment(store)
    }
    // Roughly 80×50 cells of the default font, plus the padding — .nfo files
    // run long, so the extra height is worth more than the width.
    .defaultSize(width: 700, height: 920)
    .commands {
      // Replaces the stock Zoom In/Out, which act on the window, not the text.
      CommandGroup(after: .toolbar) {
        Button("Zoom In") { store.zoom(by: 1) }
          .keyboardShortcut("+")
          .disabled(!store.canZoom(by: 1))
        Button("Zoom Out") { store.zoom(by: -1) }
          .keyboardShortcut("-")
          .disabled(!store.canZoom(by: -1))
        Button("Actual Size") { store.settings.fontScale = 1 }
          .keyboardShortcut("0")
          .disabled(store.settings.fontScale == 1)
        Divider()
      }
    }

    // "Settings" is the HIG term since Ventura; "Preferences" is retired.
    Settings {
      PreferencesView()
        .environment(store)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
    }
    .windowResizability(.contentSize)
  }
}

/// An open document: read-only until the lock in the toolbar says otherwise.
struct NFODocumentView: View {
  @Binding var document: NFODocument
  @Environment(SettingsStore.self) private var store
  @State private var isEditable = false

  var body: some View {
    NFOTextView(
      text: $document.text,
      columns: document.columns,
      settings: store.settings,
      isEditable: isEditable
    )
    .toolbar {
      Toggle(isOn: $isEditable) {
        Label(
          isEditable ? "Lock" : "Unlock",
          systemImage: isEditable ? "lock.open.fill" : "lock.fill")
      }
      .help(isEditable ? "Make this file read-only" : "Allow editing this file")
    }
  }
}

struct PreferencesView: View {
  @Environment(SettingsStore.self) private var store
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
    @Bindable var store = store
    let settings = store.settings

    return Form {
      Section {
        Picker("Font:", selection: $store.settings.fontFamily) {
          ForEach(PreviewSettings.bundledFontFamilies, id: \.self) { family in
            Text(family).tag(family)
          }
          Divider()
          ForEach(Self.monospaceFamilies, id: \.self) { family in
            Text(family).tag(family)
          }
        }

        // Powers of two only — a pixel font at 1.5× is a blurry pixel font.
        // ⌘+ / ⌘- / ⌘0 in a document window move this same control.
        Picker("Size:", selection: $store.settings.fontScale) {
          ForEach(PreviewSettings.fontScales, id: \.self) { scale in
            Text("\(scale.formatted(.number))×").tag(scale)
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
        Picker("Appearance:", selection: $store.settings.colorMode) {
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
          // Assigning the defaults saves like any other edit.
          Button("Reset") { store.settings = PreviewSettings() }
            .disabled(settings == PreviewSettings())
        }
      }
    }
    .formStyle(.grouped)
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
      get: { Color(hex: store.settings[keyPath: path]) },
      set: { store.settings[keyPath: path] = $0.hex }
    )
  }
}
