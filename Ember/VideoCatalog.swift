import Foundation

enum VideoCategory: String, Codable, CaseIterable, Hashable {
    case followAlong
    case lightShort

    var title: String {
        switch self {
        case .followAlong: "Longs"
        case .lightShort: "Shorts"
        }
    }

    var detail: String {
        switch self {
        case .followAlong:
            "Technique lessons, about 10–30 minutes. Pick one yourself."
        case .lightShort:
            "Light sports clips for a rest of about 3 minutes."
        }
    }
}

struct CatalogVideo: Codable, Equatable, Hashable, Identifiable {
    var title: String
    var durationSeconds: Int
    var category: VideoCategory
    var youtubeID: String
    var sourceCredit: String

    var id: String { youtubeID }
}

struct VideoCatalog: Codable, Equatable {
    var items: [CatalogVideo]

    func items(in category: VideoCategory) -> [CatalogVideo] {
        items.filter { $0.category == category }
    }

    static func decode(_ data: Data) throws -> VideoCatalog {
        let catalog = try JSONDecoder().decode(VideoCatalog.self, from: data)
        try catalog.validate()
        return catalog
    }

    func validate() throws {
        if items.isEmpty { throw CatalogError.empty }
        var seen = Set<String>()
        for item in items {
            let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let credit = item.sourceCredit.trimmingCharacters(in: .whitespacesAndNewlines)
            if title.isEmpty || credit.isEmpty || item.durationSeconds <= 0 {
                throw CatalogError.invalidItem(item.youtubeID)
            }
            if !YouTubeVideoID.isValid(item.youtubeID) {
                throw CatalogError.invalidYouTubeID(item.youtubeID)
            }
            if !seen.insert(item.youtubeID).inserted {
                throw CatalogError.duplicateYouTubeID(item.youtubeID)
            }
        }
    }
}

enum CatalogError: Error, Equatable {
    case empty
    case invalidItem(String)
    case invalidYouTubeID(String)
    case duplicateYouTubeID(String)
}

enum YouTubeVideoID {
    /// Official watch IDs are 11 characters. File names and page URLs are rejected
    /// so the player can only be handed an ID, never a downloaded media path.
    static func isValid(_ value: String) -> Bool {
        value.range(of: #"^[A-Za-z0-9_-]{11}$"#, options: .regularExpression) != nil
    }
}

struct VideoLibrary {
    var videos: [CatalogVideo]
    var problem: String?

    func items(in category: VideoCategory) -> [CatalogVideo] {
        videos.filter { $0.category == category }
    }

    static func load(bundle: Bundle = .main) -> VideoLibrary {
        guard let url = bundle.url(forResource: "VideoCatalog", withExtension: "json") else {
            return VideoLibrary(videos: [], problem: "The video catalog is not in the app.")
        }
        do {
            let data = try Data(contentsOf: url)
            let catalog = try VideoCatalog.decode(data)
            return VideoLibrary(videos: catalog.items, problem: nil)
        } catch {
            return VideoLibrary(videos: [], problem: "The video catalog could not be read.")
        }
    }
}
