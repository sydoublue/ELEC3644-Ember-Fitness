import SwiftUI
import WebKit

/// Holds the live YouTube IFrame so a rest alarm can pause it without saving any media.
final class YouTubePlayback {
    weak var webView: WKWebView?

    func pause() {
        webView?.evaluateJavaScript("emberPause();", completionHandler: nil)
    }
}

enum YouTubePlaybackProblem: Equatable {
    case needsNetwork
    case unavailable

    var title: String {
        switch self {
        case .needsNetwork: "Needs network"
        case .unavailable: "YouTube can't play this one"
        }
    }

    var message: String {
        switch self {
        case .needsNetwork:
            "This video is streamed from YouTube, so it needs a network connection. Ember does not keep a copy on the phone."
        case .unavailable:
            "The YouTube player refused this video."
        }
    }
}

enum YouTubeEmbed {
    /// YouTube requires a Referer that identifies the app. For HTML loaded in
    /// WKWebView, that value comes from the page base URL, using the bundle ID.
    static var refererURL: URL {
        let id = (Bundle.main.bundleIdentifier ?? "com.ember.fitness").lowercased()
        return URL(string: "https://\(id)") ?? URL(string: "https://com.ember.fitness")!
    }

    /// `loadHTMLString` navigates to `refererURL` before any YouTube frame exists.
    /// That host has to stay allowed, or WebKit cancels the player page and the
    /// spinner never leaves.
    static func allowsPlayerNavigation(_ url: URL?) -> Bool {
        guard let url else { return false }
        if url.scheme == "about" { return true }
        guard url.scheme == "https" || url.scheme == "http" else { return false }
        guard let host = url.host?.lowercased() else { return false }
        if host == refererURL.host?.lowercased() { return true }
        let suffixes = [
            "youtube.com",
            "youtube-nocookie.com",
            "youtu.be",
            "googlevideo.com",
            "ytimg.com",
            "ggpht.com",
            "gstatic.com",
            "google.com",
            "googleapis.com",
            "googleusercontent.com"
        ]
        return suffixes.contains { host == $0 || host.hasSuffix(".\($0)") }
    }
}

enum YouTubeIFrameHTML {
    static func page(for youtubeID: String) -> String? {
        guard YouTubeVideoID.isValid(youtubeID) else { return nil }
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <meta name="referrer" content="strict-origin-when-cross-origin">
        <style>
          html, body { margin: 0; padding: 0; height: 100%; background: #000; }
          #player { position: absolute; inset: 0; }
        </style>
        </head>
        <body>
        <div id="player"></div>
        <script src="https://www.youtube.com/iframe_api"></script>
        <script>
          var player;
          var pauseRequested = false;
          function onYouTubeIframeAPIReady() {
            player = new YT.Player('player', {
              width: '100%',
              height: '100%',
              videoId: '\(youtubeID)',
              playerVars: {
                playsinline: 1,
                rel: 0,
                origin: window.location.origin
              },
              events: {
                onReady: function() {
                  if (pauseRequested && player && player.pauseVideo) { player.pauseVideo(); }
                  window.webkit.messageHandlers.ember.postMessage('ready');
                },
                onError: function(event) {
                  window.webkit.messageHandlers.ember.postMessage('error:' + event.data);
                }
              }
            });
          }
          function emberPause() {
            pauseRequested = true;
            if (player && player.pauseVideo) { player.pauseVideo(); }
          }
        </script>
        </body>
        </html>
        """
    }
}

/// Official YouTube IFrame Player API inside WKWebView.
/// The web view uses a non-persistent data store, so Ember does not keep YouTube media on disk.
struct YouTubeIFramePlayer: UIViewRepresentable {
    var videoID: String
    var pauseToken: Int
    var playback: YouTubePlayback
    var onReady: () -> Void
    var onPlaybackFailed: (YouTubePlaybackProblem) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onReady: onReady, onPlaybackFailed: onPlaybackFailed)
    }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "ember")
        let pauseScript = WKUserScript(
            source: """
            function emberPause() {
              var videos = document.querySelectorAll('video');
              for (var i = 0; i < videos.length; i++) { videos[i].pause(); }
              if (window.player && player.pauseVideo) { player.pauseVideo(); }
            }
            """,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        )
        controller.addUserScript(pauseScript)
        configuration.userContentController = controller

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.scrollView.isScrollEnabled = false
        webView.allowsBackForwardNavigationGestures = false
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        context.coordinator.webView = webView
        playback.webView = webView
        if let html = YouTubeIFrameHTML.page(for: videoID) {
            webView.loadHTMLString(html, baseURL: YouTubeEmbed.refererURL)
        } else {
            onPlaybackFailed(.unavailable)
        }
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        playback.webView = webView
        context.coordinator.onReady = onReady
        context.coordinator.onPlaybackFailed = onPlaybackFailed
        context.coordinator.pauseIfNeeded(token: pauseToken, webView: webView)
    }

    static func dismantleUIView(_ webView: WKWebView, coordinator: Coordinator) {
        webView.configuration.userContentController.removeScriptMessageHandler(forName: "ember")
        webView.stopLoading()
        coordinator.webView = nil
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var onReady: () -> Void
        var onPlaybackFailed: (YouTubePlaybackProblem) -> Void
        weak var webView: WKWebView?
        private var sawInitialToken = false
        private var lastToken = 0

        init(onReady: @escaping () -> Void, onPlaybackFailed: @escaping (YouTubePlaybackProblem) -> Void) {
            self.onReady = onReady
            self.onPlaybackFailed = onPlaybackFailed
        }

        func pauseIfNeeded(token: Int, webView: WKWebView) {
            if !sawInitialToken {
                sawInitialToken = true
                lastToken = token
                return
            }
            guard token != lastToken else { return }
            lastToken = token
            webView.evaluateJavaScript("emberPause();", completionHandler: nil)
        }

        nonisolated func userContentController(
            _ userContentController: WKUserContentController,
            didReceive message: WKScriptMessage
        ) {
            let body = message.body as? String ?? ""
            Task { @MainActor in
                if body == "ready" {
                    self.onReady()
                } else if body.hasPrefix("error:") {
                    let code = Int(body.dropFirst("error:".count)) ?? 0
                    let problem: YouTubePlaybackProblem = (code == 100 || code == 101 || code == 150) ? .unavailable : .needsNetwork
                    self.onPlaybackFailed(problem)
                }
            }
        }

        nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                self.onReady()
            }
        }

        nonisolated func webView(
            _ webView: WKWebView,
            didFailProvisionalNavigation navigation: WKNavigation!,
            withError error: Error
        ) {
            report(error)
        }

        nonisolated func webView(
            _ webView: WKWebView,
            didFail navigation: WKNavigation!,
            withError error: Error
        ) {
            report(error)
        }

        nonisolated func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            if navigationAction.navigationType == .linkActivated {
                return .cancel
            }
            return YouTubeEmbed.allowsPlayerNavigation(navigationAction.request.url) ? .allow : .cancel
        }

        nonisolated private func report(_ error: Error) {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }
            if nsError.domain == "WebKitErrorDomain" && (nsError.code == 102 || nsError.code == 204) { return }
            Task { @MainActor in
                self.onPlaybackFailed(.needsNetwork)
            }
        }
    }
}

struct YouTubePlayerScreen: View {
    let video: CatalogVideo
    @Environment(VideoLounge.self) private var lounge
    @State private var ready = false
    @State private var problem: YouTubePlaybackProblem?
    @State private var attempt = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let remaining = lounge.remaining {
                    RestBanner(remaining: remaining) { lounge.cancelRest() }
                }
                stage
                Text(video.title)
                    .font(.ember(22, .bold))
                    .foregroundStyle(Theme.ink)
                Text(video.sourceCredit)
                    .font(.ember(17, .semibold))
                    .foregroundStyle(.secondary)
                Text("\(Fmt.clock(video.durationSeconds)) · \(video.category.title)")
                    .font(.ember(15))
                    .foregroundStyle(.secondary)
                Text("Played in the YouTube player. Ember does not download or store the video, and it does not play offline.")
                    .font(.ember(13))
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .background(Theme.background)
        .navigationTitle("Video")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: lounge.pauseRequests) { _, _ in
            lounge.playback.pause()
        }
    }

    @ViewBuilder
    private var stage: some View {
        if problem == nil {
            ZStack {
                YouTubeIFramePlayer(
                    videoID: video.youtubeID,
                    pauseToken: lounge.pauseRequests,
                    playback: lounge.playback,
                    onReady: { ready = true },
                    onPlaybackFailed: { failure in
                        problem = failure
                    }
                )
                .id(attempt)
                if !ready {
                    ProgressView()
                        .tint(.white)
                        .allowsHitTesting(false)
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .background(Color.black, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
        } else {
            problemCard
        }
    }

    private var problemCard: some View {
        let shown = problem ?? .needsNetwork
        return VStack(alignment: .leading, spacing: 8) {
            Text(shown.title)
                .font(.ember(17, .semibold))
                .foregroundStyle(Theme.ink)
            Text(shown.message)
                .font(.ember(15))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try again") {
                ready = false
                problem = nil
                attempt += 1
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(Theme.ember)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
    }
}
