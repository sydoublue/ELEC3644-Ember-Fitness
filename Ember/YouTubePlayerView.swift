import Network
import SwiftUI
import WebKit

/// Holds the live YouTube IFrame so a rest alarm can pause it without saving any media.
final class YouTubePlayback {
    weak var webView: WKWebView?

    func pause() {
        webView?.evaluateJavaScript("emberPause();", completionHandler: nil)
    }
}

/// Cached path status. The monitor stays off the main actor so a rest screen can ask
/// "is there a network?" without downloading any video.
nonisolated final class NetworkWatch: @unchecked Sendable {
    static let shared = NetworkWatch()
    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var online = true

    var isOnline: Bool {
        lock.lock()
        defer { lock.unlock() }
        return online
    }

    private init() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.store(path.status == .satisfied)
        }
        monitor.start(queue: DispatchQueue(label: "ember.network"))
        store(monitor.currentPath.status == .satisfied)
    }

    private func store(_ value: Bool) {
        lock.lock()
        online = value
        lock.unlock()
    }
}

enum NetworkStatus {
    static func isConnected() -> Bool {
        NetworkWatch.shared.isOnline
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

        nonisolated func webView(
            _ webView: WKWebView,
            decidePolicyFor navigationAction: WKNavigationAction
        ) async -> WKNavigationActionPolicy {
            if navigationAction.navigationType == .linkActivated {
                return .cancel
            }
            return Self.allows(navigationAction.request.url) ? .allow : .cancel
        }

        nonisolated private func report(_ error: Error) {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }
            Task { @MainActor in
                self.onPlaybackFailed(.needsNetwork)
            }
        }

        nonisolated private static func allows(_ url: URL?) -> Bool {
            guard let url else { return false }
            if url.scheme == "about" { return true }
            guard let host = url.host?.lowercased() else { return false }
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
}

struct YouTubePlayerScreen: View {
    let video: CatalogVideo
    @Environment(VideoLounge.self) private var lounge
    @State private var online = NetworkStatus.isConnected()
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
                    .font(.headline)
                    .foregroundStyle(.secondary)
                Text("\(clock(video.durationSeconds)) · \(video.category.title)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text("Played in the YouTube player. Ember does not download or store the video, and it does not play offline.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(24)
        }
        .background(EmberColor.paper)
        .navigationTitle("Video")
        .navigationBarTitleDisplayMode(.inline)
        .task(id: attempt) {
            guard problem == nil, online else { return }
            try? await Task.sleep(for: .seconds(20))
            if !ready, problem == nil {
                problem = .needsNetwork
            }
        }
        .task {
            while !Task.isCancelled {
                let connected = NetworkStatus.isConnected()
                if connected != online { online = connected }
                if !connected, problem == nil {
                    lounge.playback.pause()
                    problem = .needsNetwork
                }
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .onChange(of: lounge.pauseRequests) { _, _ in
            lounge.playback.pause()
        }
    }

    @ViewBuilder
    private var stage: some View {
        if online && problem == nil {
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
                .font(.headline)
                .foregroundStyle(EmberColor.ink)
            Text(shown.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Try again") {
                online = NetworkStatus.isConnected()
                if online {
                    ready = false
                    problem = nil
                    attempt += 1
                } else {
                    problem = .needsNetwork
                }
            }
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(EmberColor.accent)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.white, in: RoundedRectangle(cornerRadius: 14))
    }
}
