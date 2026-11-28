import Foundation
import UIKit
import UserNotifications

enum RestReminderClock {
    static let minimumMinutes = 1
    static let maximumMinutes = 5
    static let defaultMinutes = 3

    static func clampedMinutes(_ value: Int) -> Int {
        min(maximumMinutes, max(minimumMinutes, value))
    }
}

protocol RestNotifying {
    func schedule(after seconds: Int)
    func cancel()
}

enum RestNotificationID {
    static let request = "com.ember.fitness.video.rest"
}

enum RestNotificationAccess {
    static func requestIfNeeded() async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await center.requestAuthorization(options: [.alert, .sound])
        }
    }
}

struct LiveRestNotifier: RestNotifying {
    func schedule(after seconds: Int) {
        let content = UNMutableNotificationContent()
        content.title = "Rest is over"
        content.body = "Time to start your next set. Playback is paused."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: TimeInterval(max(1, seconds)),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: RestNotificationID.request,
            content: content,
            trigger: trigger
        )
        UNUserNotificationCenter.current().add(request)
    }

    func cancel() {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [RestNotificationID.request])
    }
}

/// Forwards a delivered or foreground rest notification into the in-app timer.
final class RestNotificationBridge: NSObject, UNUserNotificationCenterDelegate {
    var onFire: (() -> Void)?

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        guard notification.request.identifier == RestNotificationID.request else {
            return [.banner, .sound]
        }
        await MainActor.run { self.onFire?() }
        return [.sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        guard response.notification.request.identifier == RestNotificationID.request else { return }
        await MainActor.run { self.onFire?() }
    }
}

/// Gym-rest countdown for the Video tab. It does not belong to a Daily Pick session.
@Observable
final class VideoLounge {
    let playback = YouTubePlayback()
    private let notifier: RestNotifying
    private let bridge = RestNotificationBridge()

    var restMinutes = RestReminderClock.defaultMinutes
    private(set) var remaining: Int?
    var showRestAlert = false
    var pauseRequests = 0
    private var fireAt: Date?

    init(notifier: RestNotifying = LiveRestNotifier(), receivesNotifications: Bool = true) {
        self.notifier = notifier
        if receivesNotifications {
            bridge.onFire = { [weak self] in
                self?.finishRest()
            }
            UNUserNotificationCenter.current().delegate = bridge
        }
    }

    func startRest(minutes: Int, now: Date = .now) {
        let clamped = RestReminderClock.clampedMinutes(minutes)
        restMinutes = clamped
        let seconds = clamped * 60
        if fireAt != nil {
            notifier.cancel()
        }
        fireAt = now.addingTimeInterval(TimeInterval(seconds))
        remaining = seconds
        showRestAlert = false
        notifier.schedule(after: seconds)
    }

    func cancelRest() {
        guard fireAt != nil || remaining != nil else { return }
        fireAt = nil
        remaining = nil
        notifier.cancel()
    }

    func tick(now: Date = .now) {
        guard let fireAt else { return }
        let left = Int(fireAt.timeIntervalSince(now).rounded(.up))
        if left <= 0 {
            finishRest()
        } else if remaining != left {
            remaining = left
        }
    }

    func finishRest() {
        guard fireAt != nil else { return }
        fireAt = nil
        remaining = nil
        notifier.cancel()
        pauseRequests += 1
        playback.pause()
        showRestAlert = true
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}
