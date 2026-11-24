import SwiftUI
import WebKit

/// A YouTube video result.
struct YouTubeVideo: Identifiable, Hashable, Decodable {
    let id: String
    let title: String
    let channel: String

    var thumbnailURL: URL? { URL(string: "https://i.ytimg.com/vi/\(id)/hqdefault.jpg") }
    var watchURL: URL? { URL(string: "https://www.youtube.com/watch?v=\(id)") }
}

/// Finds demo videos. Uses the YouTube Data API when a key is set (Settings → YouTube),
/// otherwise the app falls back to an in-app YouTube search page.
enum YouTubeService {

    enum ServiceError: LocalizedError {
        case noKey, badResponse(String)
        var errorDescription: String? {
            switch self {
            case .noKey: return "No YouTube API key set."
            case .badResponse(let msg): return msg
            }
        }
    }

    private struct SearchResponse: Decodable {
        struct Item: Decodable {
            struct ID: Decodable { let videoId: String? }
            struct Snippet: Decodable { let title: String; let channelTitle: String }
            let id: ID
            let snippet: Snippet
        }
        let items: [Item]
    }

    private static var cache: [String: [YouTubeVideo]] = [:]

    /// The key from Settings, or one baked in at build time via Info.plist `YouTubeAPIKey`.
    static func apiKey(from settings: AppSettings) -> String? {
        let fromSettings = settings.youtubeAPIKey.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fromSettings.isEmpty { return fromSettings }
        if let bundled = Bundle.main.object(forInfoDictionaryKey: "YouTubeAPIKey") as? String,
           !bundled.trimmingCharacters(in: .whitespaces).isEmpty, !bundled.hasPrefix("$(") {
            return bundled
        }
        return nil
    }

    @MainActor
    static func search(_ query: String, key: String?, limit: Int = 6) async throws -> [YouTubeVideo] {
        guard let key else { throw ServiceError.noKey }
        if let cached = cache[query] { return cached }
        var comps = URLComponents(string: "https://www.googleapis.com/youtube/v3/search")!
        comps.queryItems = [
            URLQueryItem(name: "part", value: "snippet"),
            URLQueryItem(name: "type", value: "video"),
            URLQueryItem(name: "videoEmbeddable", value: "true"),
            URLQueryItem(name: "safeSearch", value: "strict"),
            URLQueryItem(name: "videoDuration", value: "short"),
            URLQueryItem(name: "maxResults", value: String(limit)),
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "key", value: key),
        ]
        guard let url = comps.url else { throw ServiceError.badResponse("Bad URL") }
        var request = URLRequest(url: url)
        if let bundleID = Bundle.main.bundleIdentifier {
            request.setValue(bundleID, forHTTPHeaderField: "X-Ios-Bundle-Identifier")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw ServiceError.badResponse("YouTube returned an error. Check your API key in Settings.")
        }
        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        let videos = decoded.items.compactMap { item -> YouTubeVideo? in
            guard let id = item.id.videoId else { return nil }
            return YouTubeVideo(id: id, title: decodeEntities(item.snippet.title), channel: item.snippet.channelTitle)
        }
        cache[query] = videos
        return videos
    }

    static func searchPageURL(_ query: String) -> URL {
        var comps = URLComponents(string: "https://m.youtube.com/results")!
        comps.queryItems = [URLQueryItem(name: "search_query", value: query)]
        return comps.url!
    }

    private static func decodeEntities(_ s: String) -> String {
        s.replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
    }
}

// MARK: - Embedded player

/// Plays a YouTube video inline using the official iframe embed.
struct YouTubePlayerView: UIViewRepresentable {
    let videoID: String

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        config.mediaTypesRequiringUserActionForPlayback = []
        let web = WKWebView(frame: .zero, configuration: config)
        web.isOpaque = false
        web.backgroundColor = .black
        web.scrollView.isScrollEnabled = false
        return web
    }

    func updateUIView(_ web: WKWebView, context: Context) {
        guard context.coordinator.loadedID != videoID else { return }
        context.coordinator.loadedID = videoID
        // YouTube requires a referrer for embeds, so load from an https base URL that matches `origin`.
        let bundleID = Bundle.main.bundleIdentifier ?? "app.ember.fitness"
        let origin = "https://\(bundleID)"
        let html = """
        <!DOCTYPE html><html><head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <meta name="referrer" content="strict-origin-when-cross-origin">
        <style>html,body{margin:0;padding:0;background:#000;height:100%;overflow:hidden}
        iframe{position:absolute;top:0;left:0;width:100%;height:100%;border:0}</style></head>
        <body><iframe src="https://www.youtube-nocookie.com/embed/\(videoID)?playsinline=1&rel=0&modestbranding=1&autoplay=1&origin=\(origin)"
        allow="autoplay; encrypted-media; picture-in-picture; fullscreen" allowfullscreen
        referrerpolicy="strict-origin-when-cross-origin"></iframe></body></html>
        """
        web.loadHTMLString(html, baseURL: URL(string: origin))
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var loadedID: String? }
}

/// Fallback: a YouTube search page inside the app (no API key needed).
struct WebPageView: UIViewRepresentable {
    let url: URL

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
        let web = WKWebView(frame: .zero, configuration: config)
        web.allowsBackForwardNavigationGestures = true
        web.load(URLRequest(url: url))
        return web
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}

// MARK: - Demo section used on exercise screens

struct VideoDemosSection: View {
    let exercise: Exercise
    @Environment(EmberStore.self) private var store
    @Environment(\.openURL) private var openURL

    @State private var videos: [YouTubeVideo] = []
    @State private var isLoading = false
    @State private var errorText: String?
    @State private var playing: YouTubeVideo?
    @State private var showSearchPage = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Video demos", systemImage: "play.rectangle.fill")
                    .font(.ember(18, .bold))
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text("YouTube").font(.ember(12, .semibold)).foregroundStyle(.red)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Color.red.opacity(0.1), in: Capsule())
            }

            if let id = exercise.youtubeID {
                featured(YouTubeVideo(id: id, title: exercise.name, channel: "Curated"))
            }

            if isLoading {
                HStack { ProgressView(); Text("Finding demos…").font(.ember(14)).foregroundStyle(Theme.inkSoft) }
            } else if !videos.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(videos) { video in
                            Button { playing = video } label: { videoCard(video) }
                                .buttonStyle(PressableStyle())
                        }
                    }
                }
            } else {
                searchCard
            }
            if let errorText {
                Text(errorText).font(.ember(12)).foregroundStyle(Theme.inkSoft)
            }
        }
        .task(id: exercise.id) { await load() }
        .sheet(item: $playing) { video in
            VideoPlayerSheet(video: video)
        }
        .sheet(isPresented: $showSearchPage) {
            NavigationStack {
                WebPageView(url: YouTubeService.searchPageURL(exercise.videoQuery))
                    .ignoresSafeArea(edges: .bottom)
                    .navigationTitle(exercise.name)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) { Button("Done") { showSearchPage = false } }
                    }
            }
        }
    }

    private func load() async {
        guard let key = YouTubeService.apiKey(from: store.settings) else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            videos = try await YouTubeService.search(exercise.videoQuery, key: key)
            errorText = nil
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func featured(_ video: YouTubeVideo) -> some View {
        Button { playing = video } label: {
            thumbnail(video, width: nil, height: 190)
        }
        .buttonStyle(PressableStyle())
    }

    private func videoCard(_ video: YouTubeVideo) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            thumbnail(video, width: 220, height: 124)
            Text(video.title).font(.ember(14, .semibold)).foregroundStyle(Theme.ink).lineLimit(2)
                .multilineTextAlignment(.leading)
            Text(video.channel).font(.ember(12)).foregroundStyle(Theme.inkSoft).lineLimit(1)
        }
        .frame(width: 220, alignment: .leading)
    }

    private func thumbnail(_ video: YouTubeVideo, width: CGFloat?, height: CGFloat) -> some View {
        Theme.surfaceMuted
            .frame(width: width, height: height)
            .frame(maxWidth: width == nil ? .infinity : nil)
            .overlay {
                AsyncImage(url: video.thumbnailURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Theme.surfaceMuted
                    }
                }
            }
            .overlay {
                LinearGradient(colors: [.clear, .black.opacity(0.35)], startPoint: .top, endPoint: .bottom)
            }
            .overlay {
                Image(systemName: "play.fill")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
    }

    private var searchCard: some View {
        Button { showSearchPage = true } label: {
            HStack(spacing: 14) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.red.opacity(0.12))
                    Image(systemName: "play.rectangle.fill").font(.system(size: 26)).foregroundStyle(.red)
                }
                .frame(width: 64, height: 48)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Watch \(exercise.name) demos").font(.ember(15, .semibold)).foregroundStyle(Theme.ink)
                    Text("Opens YouTube inside Ember").font(.ember(13)).foregroundStyle(Theme.inkSoft)
                }
                Spacer()
                Image(systemName: "chevron.right").foregroundStyle(Theme.inkSoft)
            }
            .padding(12)
            .background(Theme.surfaceMuted, in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
        }
        .buttonStyle(PressableStyle())
    }
}

struct VideoPlayerSheet: View {
    let video: YouTubeVideo
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 16) {
                YouTubePlayerView(videoID: video.id)
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
                Text(video.title).font(.ember(18, .bold)).foregroundStyle(Theme.ink)
                Text(video.channel).font(.ember(14)).foregroundStyle(Theme.inkSoft)
                if let url = video.watchURL {
                    Button { openURL(url) } label: {
                        Label("Open in YouTube", systemImage: "arrow.up.right.square")
                    }
                    .buttonStyle(EmberButtonStyle(kind: .secondary, compact: true))
                }
                Spacer()
            }
            .padding()
            .emberBackground()
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
