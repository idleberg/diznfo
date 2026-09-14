import AppKit
import NFOKit
import QuickLookUI
import WebKit

/// QuickLook preview for `.nfo` / `.diz` / `.ans` files.
@objc(PreviewViewController)
final class PreviewViewController: NSViewController, QLPreviewingController {
  /// Fonts: The Ultimate Oldschool PC Font Pack by VileR (int10h.org), CC BY-SA 4.0.
  /// Bundled unmodified; see Resources/Fonts/FONT-LICENSE.txt.
  ///
  /// Only one file is ever embedded in a page — the family the user picked, or
  /// the default when they picked something installed on the system instead.
  private static func bundledFont(for settings: PreviewSettings) -> (family: String, data: Data)? {
    let family =
      PreviewSettings.bundledResource(for: settings.fontFamily) != nil
      ? settings.fontFamily : PreviewSettings.defaultFontFamily
    guard let resource = PreviewSettings.bundledResource(for: family),
      let url = Bundle.main.url(forResource: resource, withExtension: "ttf"),
      let data = try? Data(contentsOf: url)
    else { return nil }
    return (family, data)
  }

  private lazy var webView: WKWebView = {
    let configuration = WKWebViewConfiguration()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = false
    let webView = WKWebView(frame: .zero, configuration: configuration)
    webView.navigationDelegate = loadWaiter
    return webView
  }()

  private let loadWaiter = LoadWaiter()

  override func loadView() {
    view = webView
  }

  func preparePreviewOfFile(at url: URL) async throws {
    let data = try Data(contentsOf: url)
    let isDark = view.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua

    let settings = PreviewSettings.load()
    let html = NFORenderer.html(
      for: data,
      pathExtension: url.pathExtension,
      settings: settings,
      font: Self.bundledFont(for: settings),
      isDarkAppearance: isDark
    )
    // QuickLook displays the view as soon as this returns, so wait for the
    // page to actually finish loading — otherwise larger files show blank.
    try await loadWaiter.load { webView.loadHTMLString(html, baseURL: nil) }
  }
}

/// Bridges `WKNavigationDelegate` callbacks back to `async`.
@MainActor
private final class LoadWaiter: NSObject, WKNavigationDelegate {
  private var continuation: CheckedContinuation<Void, Error>?

  func load(_ start: () -> Void) async throws {
    try await withCheckedThrowingContinuation { continuation in
      self.continuation = continuation
      start()
    }
  }

  private func finish(_ result: Result<Void, Error>) {
    continuation?.resume(with: result)
    continuation = nil
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    finish(.success(()))
  }

  func webView(
    _ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error
  ) {
    finish(.failure(error))
  }

  func webView(
    _ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: Error
  ) {
    finish(.failure(error))
  }

  /// A crashed content process fires no navigation callback at all — without
  /// this the await never returns and QuickLook spins forever.
  func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
    finish(
      .failure(
        NSError(
          domain: "com.idleberg.Diznfo", code: 1,
          userInfo: [NSLocalizedDescriptionKey: "The web content process terminated."])))
  }
}
