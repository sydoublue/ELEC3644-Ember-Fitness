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
            "Playback needs a network connection. This list is on your phone, but the YouTube video is not downloaded or saved here."
        case .unavailable:
            "The YouTube player refused this video. Nothing was saved on this phone."
        }
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
                origin: 'https://www.youtube.com'
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
            webView.loadHTMLString(html, baseURL: URL(string: "https://www.youtube.com"))
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

        nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                self.onReady()
            }
        }

        nonisolated func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            if navigationAction.navigationType == .linkActivated {
                return .cancel
            }
            guard let url = navigationAction.request.url else { return .allow }
            switch url.scheme?.lowercased() {
            case "about", "https", "http":
                return .allow
            default:
                return .cancel
            }
        }

        nonisolated private func report(_ error: Error) {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }
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
                    .font(.title2.bold())
                    .foregroundStyle(EmberColor.ink)
                Text(video.sourceCredit)
                    .font(.title3)
                    .foregroundStyle(EmberColor.ink)
                Text("\(clock(video.durationSeconds)) · \(video.category.rowNote)")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                Text(video.category.detail)
                    .font(.body)
                    .foregroundStyle(EmberColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Played in the YouTube player. Ember does not download or store the video.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .background(EmberColor.paper)
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
            .background(Color.black, in: RoundedRectangle(cornerRadius: 14))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        } else {
            problemCard
        }
    }

    private var problemCard: some View {
        let shown = problem ?? .needsNetwork
        return VStack(alignment: .leading, spacing: 8) {
            Text(shown.title)
                .font(.title3.bold())
                .foregroundStyle(EmberColor.ink)
            Text(shown.message)
                .font(.body)
                .foregroundStyle(EmberColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try again") {
                ready = false
                problem = nil
                attempt += 1
            }
            .font(.body.weight(.semibold))
            .foregroundStyle(EmberColor.accent)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
    }
}
