import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Wrapper around Apple's on-device language model (Apple Intelligence, iOS 26+).
/// On older devices or when it's off, Ember's coach uses its built-in rule-based replies instead.
enum LocalAI {

    enum AIError: Error { case unavailable }

    static var isAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            if case .available = SystemLanguageModel.default.availability { return true }
        }
        #endif
        return false
    }

    /// One-shot response. Instructions are folded into the prompt to keep the API surface minimal.
    static func respond(instructions: String, prompt: String) async throws -> String {
        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard isAvailable else { throw AIError.unavailable }
            let session = LanguageModelSession()
            let full = """
            \(instructions)

            ---
            \(prompt)
            """
            let response = try await session.respond(to: full)
            return response.content.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        #endif
        throw AIError.unavailable
    }
}
