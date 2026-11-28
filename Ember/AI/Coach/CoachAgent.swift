import Foundation
import Observation

/// What the user asked for, extracted from free text. Deterministic so it works offline and is testable.
struct CoachIntent: Equatable {
    var wantsWorkout = false
    var wantsStats = false
    var minutes: Int?
    var feeling: Feeling?
    var location: Location?
    var discomfort: Set<BodyArea> = []
    var focus: [MovementCategory] = []
    var exerciseID: String?
    var safetyConcern = false
}

enum IntentParser {

    private static func has(_ text: String, _ words: [String]) -> Bool {
        words.contains { text.contains($0) }
    }

    static func parse(_ raw: String) -> CoachIntent {
        let text = " " + raw.lowercased().replacingOccurrences(of: "’", with: "'") + " "
        var intent = CoachIntent()

        // Minutes
        if let match = text.range(of: #"(\d{1,3})\s*-?\s*(min|mins|minute|minutes|m)\b"#, options: .regularExpression) {
            let digits = text[match].prefix { $0.isNumber }
            if let n = Int(digits) { intent.minutes = min(30, max(5, n)) }
        } else if has(text, ["half an hour", "half hour"]) {
            intent.minutes = 30
        } else if has(text, ["quarter of an hour", "quarter hour"]) {
            intent.minutes = 15
        } else if has(text, ["quick", "short", "fast", "little time", "no time"]) {
            intent.minutes = 7
        }

        // Feeling (most specific first)
        if has(text, ["exhausted", "drained", "very tired", "so tired", "dead tired", "very low", "barely"]) {
            intent.feeling = .veryLow
        } else if has(text, ["tired", "sleepy", "low energy", "meh", "lazy", "sore", "gentle", "easy", "light ", "relax", "chill"]) {
            intent.feeling = .low
        } else if has(text, ["great", "pumped", "amazing", "intense", "hard workout", "beast", "challenge", "push me", "sweat"]) {
            intent.feeling = .great
        } else if has(text, ["good", "energ", "motivated", "ready"]) {
            intent.feeling = .good
        } else if has(text, [" okay ", " ok ", "fine", "normal", "alright"]) {
            intent.feeling = .okay
        }

        // Location
        if has(text, ["dorm", "roommate", "quiet", "neighbo", "downstairs", "apartment", "flat "]) {
            intent.location = .dorm
        } else if has(text, ["hotel", "travel", "airbnb", "trip"]) {
            intent.location = .hotel
        } else if has(text, ["outside", "outdoor", "park", "garden", "yard", "beach"]) {
            intent.location = .outdoors
        } else if has(text, [" home", "house", "living room"]) {
            intent.location = .home
        }

        // Body areas: discomfort vs focus
        let areaWords: [(BodyArea, [String])] = [
            (.knees, ["knee"]), (.lowerBack, ["lower back", "back pain", "my back", "back hurts", "back is"]),
            (.shoulders, ["shoulder"]), (.wrists, ["wrist"]), (.neck, ["neck"]),
            (.hips, ["hip"]), (.ankles, ["ankle"]),
        ]
        let painWords = ["hurt", "sore", "pain", "ache", "achy", "injur", "tight", "bad ", "sprain", "stiff", "avoid", "careful", "tweak", "strain", "bothering", "uncomfortable"]
        let mentionsPain = has(text, painWords)
        for (area, words) in areaWords where has(text, words) {
            if mentionsPain || has(text, words.map { "my " + $0 }) {
                intent.discomfort.insert(area)
            }
        }

        // Focus
        let focusWords: [(MovementCategory, [String])] = [
            (.push, ["arm", "chest", "upper body", "push", "tricep"]),
            (.squat, ["leg", "quad", "lower body", "thigh"]),
            (.hinge, ["glute", "butt", "booty", "hamstring", "posterior"]),
            (.core, ["abs", " core", "stomach", "belly", "six pack", "plank"]),
            (.mobility, ["stretch", "mobility", "flexib", "loosen", "stiff"]),
        ]
        for (cat, words) in focusWords where has(text, words) && !intent.focus.contains(cat) {
            // Don't treat "push-up" or "plank" questions as focus requests.
            if cat == .push && has(text, ["push up", "push-up", "pushup"]) && !has(text, ["upper body", "chest", "arm"]) { continue }
            intent.focus.append(cat)
        }

        // Exercise mention (longest name wins)
        let squashed = text.filter { $0.isLetter }
        var best: (id: String, length: Int)?
        for ex in ExerciseLibrary.all {
            let candidates = [ex.name, ex.id].map { name in name.lowercased().filter { $0.isLetter } }
            for c in candidates where c.count >= 4 && squashed.contains(c) {
                if c.count > (best?.length ?? 0) { best = (ex.id, c.count) }
            }
        }
        intent.exerciseID = best?.id

        intent.wantsStats = has(text, ["progress", "how am i doing", "this week", "streak", "stats", "my history", "how much have i"])

        let workoutWords = ["workout", "routine", "plan", "session", "build", "give me", "make me", "let's go", "lets go",
                            "train", "exercise for", "exercises for", "something for", "what should i do", "start"]
        intent.wantsWorkout = has(text, workoutWords) || intent.minutes != nil || intent.location != nil
            || (!intent.focus.isEmpty && intent.exerciseID == nil)

        intent.safetyConcern = has(text, ["chest pain", "dizzy", "faint", "can't breathe", "cant breathe", "short of breath",
                                          "sharp pain", "swollen", "swelling", "injured", "injury", "pregnan", "heart"])
        return intent
    }
}

struct ChatMessage: Identifiable, Hashable {
    enum Role { case user, coach }
    let id = UUID()
    var role: Role
    var text: String
    var plan: WorkoutPlan?
    var exerciseID: String?
}

/// Ember Coach: a small agent that understands a request, uses the workout engine as its tool,
/// and phrases replies with Apple's on-device model when available.
@Observable
final class CoachAgent {

    private(set) var messages: [ChatMessage] = []
    private(set) var isThinking = false

    private let generator = WorkoutGenerator()

    static let suggestions = [
        "10 min in my dorm, I'm tired",
        "Quick core workout, knees are sore",
        "How do I do a push-up?",
        "How am I doing this week?",
        "Something to loosen up after studying",
    ]

    init() {
        messages = [ChatMessage(role: .coach, text: "Hi! I'm Ember Coach. Tell me how much time you have, how you feel, where you are, or anything that hurts, and I'll build a workout. You can also ask me how to do a move.")]
    }

    func reset() {
        messages = Array(messages.prefix(1))
    }

    @MainActor
    func send(_ text: String, store: EmberStore) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isThinking else { return }
        messages.append(ChatMessage(role: .user, text: trimmed))
        isThinking = true
        defer { isThinking = false }

        let intent = IntentParser.parse(trimmed)
        var reply: ChatMessage

        if intent.wantsWorkout {
            reply = buildWorkoutReply(intent, store: store)
            if let plan = reply.plan, LocalAI.isAvailable {
                let prompt = "The user said: \"\(trimmed)\". You built them this plan: \(planSummary(plan)). Write a warm 2-sentence intro to the plan. Mention one reason it fits them. No lists."
                if let text = try? await LocalAI.respond(instructions: instructions(store), prompt: prompt), !text.isEmpty {
                    reply.text = text
                }
            }
        } else if let id = intent.exerciseID, let ex = ExerciseLibrary.exercise(id) {
            reply = ChatMessage(role: .coach, text: howTo(ex), exerciseID: id)
            if LocalAI.isAvailable,
               let text = try? await LocalAI.respond(instructions: instructions(store),
                                                     prompt: "Explain briefly how to do \(ex.name) with good form, in 3 short sentences. Question: \(trimmed)"),
               !text.isEmpty {
                reply.text = text
            }
        } else if intent.wantsStats {
            reply = ChatMessage(role: .coach, text: statsSummary(store))
        } else if LocalAI.isAvailable,
                  let text = try? await LocalAI.respond(instructions: instructions(store), prompt: trimmed), !text.isEmpty {
            reply = ChatMessage(role: .coach, text: text)
        } else {
            reply = ChatMessage(role: .coach, text: fallback(trimmed))
        }

        if intent.safetyConcern {
            reply.text += "\n\n⚠️ If you have pain, dizziness or an injury, please stop and check with a doctor or physio. I can only give general fitness ideas."
        }
        messages.append(reply)
    }

    // MARK: Tool: workout engine

    private func buildWorkoutReply(_ intent: CoachIntent, store: EmberStore) -> ChatMessage {
        var input = store.suggestedSetup()
        if let m = intent.minutes { input.duration = m }
        if let f = intent.feeling { input.feeling = f }
        if let l = intent.location { input.location = l }
        if !intent.discomfort.isEmpty { input.discomfort = intent.discomfort }
        input.focus = intent.focus
        if intent.focus.contains(.mobility) && intent.feeling == nil { input.feeling = .low }
        let plan = generator.generate(input)

        var understood: [String] = ["\(input.duration) min", "feeling \(input.feeling.title.lowercased())"]
        if input.location != .home { understood.append("in a \(input.location.title.lowercased())") }
        if !input.discomfort.isEmpty {
            understood.append("easy on your " + input.discomfort.sorted().map { $0.title.lowercased() }.joined(separator: " & "))
        }
        if !input.focus.isEmpty {
            understood.append("extra " + input.focus.map { $0.title.lowercased() }.joined(separator: " & "))
        }
        var text = "Got it: " + understood.joined(separator: ", ") + ". "
        if plan.items.isEmpty {
            text += "I couldn't fit any moves with those limits. Try fewer discomfort areas."
        } else {
            if plan.mainItems.contains(where: { $0.isRepWork }) {
                text += "Here's \(plan.mainItems.count) moves, with strength work in reps and \(plan.restSecondsPerItem)s rests"
            } else {
                text += "Here's \(plan.mainItems.count) moves at \(plan.workSecondsPerItem)s on / \(plan.restSecondsPerItem)s off"
            }
            text += plan.recoveryItem != nil ? ", finishing with a gentle \(plan.recoveryItem!.exercise.name.lowercased())." : "."
        }
        return ChatMessage(role: .coach, text: text, plan: plan)
    }

    private func planSummary(_ plan: WorkoutPlan) -> String {
        let names = plan.items.map { $0.exercise.name }
        return "\(plan.input.duration) minutes, difficulty \(plan.input.difficulty)/5, location \(plan.input.location.title), moves: \(names.joined(separator: ", "))"
    }

    private func howTo(_ ex: Exercise) -> String {
        var s = "\(ex.name): \(ex.instruction)\n"
        for (i, step) in ex.steps.enumerated() { s += "\n\(i + 1). \(step)" }
        if let cue = ex.cues.first { s += "\n\nTip: \(cue.lowercased())." }
        return s
    }

    private func statsSummary(_ store: EmberStore) -> String {
        let week = store.minutesThisWeek
        let goal = store.settings.weeklyGoalMinutes
        var s = "This week you've moved \(week) of your \(goal) minutes"
        s += week >= goal ? ". Goal smashed! 🔥" : ", \(goal - week) to go."
        if store.streakDays > 1 { s += " You're on a \(store.streakDays)-day streak." }
        if let fb = store.lastFeedback {
            s += " Your last Ember session felt \(fb.rating.title.lowercased())."
        }
        if let scan = store.latestScan, let top = scan.findings.first {
            s += " Your latest body scan suggests working on \(top.title.lowercased())."
        }
        if store.activities.isEmpty { s = "No activity logged yet. Want me to build a quick 10-minute session to get started?" }
        return s
    }

    private func fallback(_ text: String) -> String {
        let lower = text.lowercased()
        if lower.contains("hi") || lower.contains("hello") || lower.contains("hey") {
            return "Hey! Want a workout? Try something like \"15 minutes at home, feeling good\"."
        }
        if lower.contains("thank") { return "Anytime! 💪" }
        if lower.contains("warm") { return "A good warm-up is 2–3 minutes of arm circles, hip circles and a few slow squats. Ember's plans start gently, so you can jump right in." }
        if lower.contains("water") || lower.contains("drink") { return "Sip water before and after. For a 10–20 minute session you rarely need much during." }
        if lower.contains("sleep") || lower.contains("rest day") {
            return "Rest days matter. Try a gentle 5-minute mobility session (feeling: very low) instead of skipping completely."
        }
        return "I'm best at building workouts and explaining moves. Tell me your time, energy, place and anything that hurts, like \"10 min, tired, hotel, sore wrists\"."
    }

    private func instructions(_ store: EmberStore) -> String {
        var ctx = "You are Ember Coach inside the Ember fitness app: friendly, upbeat and concise (under 80 words). "
        ctx += "Ember does short bodyweight workouts. Never diagnose or give medical advice; for pain or injury suggest seeing a professional. "
        ctx += "User context: \(store.minutesThisWeek) active minutes this week (goal \(store.settings.weeklyGoalMinutes)). "
        if let fb = store.lastFeedback { ctx += "Last session felt \(fb.rating.title.lowercased()). " }
        if let scan = store.latestScan, !scan.findings.isEmpty {
            ctx += "Body scan noticed: \(scan.findings.map { $0.title.lowercased() }.joined(separator: ", ")). "
        }
        let name = store.settings.name.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { ctx += "Their name is \(name). " }
        return ctx
    }
}
