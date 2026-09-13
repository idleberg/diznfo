import NFOKit
import SwiftUI

/// The one live copy of the user's settings, shared by every document window
/// and the Settings scene — so a `⌘+` in a document moves the Settings picker,
/// and the picker moves every open document.
///
/// Every mutation writes straight through to the file the QuickLook extension
/// reads, which is the whole point: zooming a window *is* editing the setting.
@MainActor
@Observable
final class SettingsStore {
  var settings: PreviewSettings {
    didSet { settings.save() }
  }

  init(settings: PreviewSettings = .load()) {
    self.settings = settings
  }

  /// Moves the font scale along `PreviewSettings.fontScales`. A no-op at
  /// either end, which is also what disables the menu item.
  func zoom(by steps: Int) {
    guard let scale = PreviewSettings.fontScale(after: settings.fontScale, steps: steps) else {
      return
    }
    settings.fontScale = scale
  }

  func canZoom(by steps: Int) -> Bool {
    PreviewSettings.fontScale(after: settings.fontScale, steps: steps) != nil
  }
}
