import AVFoundation
import UIKit

/// Voice cues and haptics during a session.
final class CueSpeaker {
    private let synth = AVSpeechSynthesizer()
    var voiceEnabled = true
    var hapticsEnabled = true

    init() {
        // Duck other audio (music) instead of stopping it.
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .mixWithOthers])
    }

    func say(_ text: String) {
        guard voiceEnabled else { return }
        try? AVAudioSession.sharedInstance().setActive(true)
        let utterance = AVSpeechUtterance(string: text)
        utterance.rate = 0.5
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        synth.stopSpeaking(at: .immediate)
        synth.speak(utterance)
    }

    func tap(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        guard hapticsEnabled else { return }
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    func success() {
        guard hapticsEnabled else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Hook a player's events up to voice + haptics.
    func handle(_ event: SessionPlayer.Event, player: SessionPlayer) {
        switch event {
        case .phaseChanged(let phase):
            switch phase {
            case .getReady:
                if let first = player.current?.exercise { say("Get ready. First up, \(first.name).") }
            case .work:
                tap(.heavy)
                if let ex = player.current?.exercise {
                    say(ex.perSide ? "\(ex.name). Switch sides halfway. Go!" : "\(ex.name). Go!")
                }
            case .rest:
                tap(.medium)
                if let next = player.upNext?.exercise { say("Rest. Next, \(next.name).") } else { say("Rest.") }
            case .finished:
                break
            }
        case .countdown(let n):
            tap(.light)
            if player.phase != .getReady || n <= 3 { say("\(n)") }
        case .halfway:
            if player.current?.exercise.perSide == true { say("Switch sides.") } else { say("Halfway.") }
        case .finished:
            success()
            say("Workout complete. Nice work!")
        }
    }
}
