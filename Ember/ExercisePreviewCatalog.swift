import Foundation

/// Bundled, self-owned preview clips. Lookup reads the app bundle only.
enum ExercisePreviewCatalog {
    static let fallbackResource = "movement"
    static let fileExtension = "mp4"
    static let subdirectory = "Previews"

    /// Exercise ids that ship with their own clip, plus the shared fallback.
    static let knownIds: Set<String> = {
        var ids = Set(ExerciseLibrary.all.map(\.id))
        ids.insert("self-massage")
        ids.insert(fallbackResource)
        return ids
    }()

    static func resourceName(for exerciseId: String) -> String {
        if knownIds.contains(exerciseId) {
            return exerciseId
        }
        return fallbackResource
    }

    static func url(for exerciseId: String, bundle: Bundle = .main) -> URL? {
        let preferred = resourceName(for: exerciseId)
        var names = [preferred]
        if preferred != fallbackResource {
            names.append(fallbackResource)
        }
        for name in names {
            if let url = bundle.url(forResource: name, withExtension: fileExtension, subdirectory: subdirectory) {
                return url
            }
            if let url = bundle.url(forResource: name, withExtension: fileExtension) {
                return url
            }
        }
        return nil
    }
}
