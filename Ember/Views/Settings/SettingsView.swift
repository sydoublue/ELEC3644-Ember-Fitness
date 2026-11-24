import SwiftUI
import UserNotifications

struct SettingsView: View {
    @Environment(EmberStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var confirmReset = false
    @State private var showKeyHelp = false

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                Section("You") {
                    TextField("Your name", text: $store.settings.name)
                    Stepper(value: $store.settings.weeklyGoalMinutes, in: 30...600, step: 15) {
                        LabeledContent("Weekly goal", value: "\(store.settings.weeklyGoalMinutes) min")
                    }
                }

                Section("During workouts") {
                    Toggle("Voice cues", isOn: $store.settings.voiceCues)
                    Toggle("Haptics", isOn: $store.settings.haptics)
                }

                Section {
                    Toggle("Daily nudge", isOn: Binding(
                        get: { store.settings.reminderEnabled },
                        set: { on in
                            store.settings.reminderEnabled = on
                            Reminders.update(store.settings)
                        }))
                    if store.settings.reminderEnabled {
                        DatePicker("Time", selection: Binding(
                            get: {
                                Calendar.current.date(from: DateComponents(hour: store.settings.reminderHour,
                                                                           minute: store.settings.reminderMinute)) ?? Date()
                            },
                            set: { date in
                                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                                store.settings.reminderHour = c.hour ?? 18
                                store.settings.reminderMinute = c.minute ?? 0
                                Reminders.update(store.settings)
                            }), displayedComponents: .hourAndMinute)
                    }
                } header: {
                    Text("Reminders")
                } footer: {
                    Text("A gentle local notification. Nothing leaves your phone.")
                }

                Section {
                    HStack {
                        Label("On-device AI coach", systemImage: "sparkles")
                        Spacer()
                        Text(LocalAI.isAvailable ? "Apple Intelligence" : "Built-in mode")
                            .foregroundStyle(LocalAI.isAvailable ? Theme.good : Theme.inkSoft)
                    }
                    HStack {
                        Label("Body Scan", systemImage: "figure.stand")
                        Spacer()
                        Text("Vision, on-device").foregroundStyle(Theme.good)
                    }
                } header: {
                    Text("AI")
                } footer: {
                    Text("Ember's AI runs on your iPhone. Camera frames are analysed live and never saved or uploaded.")
                }

                Section {
                    SecureField("YouTube Data API key (optional)", text: $store.settings.youtubeAPIKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("How do I get a key?") { showKeyHelp = true }
                } header: {
                    Text("Video demos")
                } footer: {
                    Text(store.settings.youtubeAPIKey.isEmpty
                         ? "Without a key, demos open YouTube search inside Ember. With a key, Ember shows a row of matching videos for every exercise."
                         : "Key saved. Exercise screens will show matching videos.")
                }

                Section {
                    LabeledContent("Apple Health", value: "Not connected")
                    LabeledContent("Apple Watch", value: "Not connected")
                } header: {
                    Text("Connections")
                } footer: {
                    Text("Coming in a future version.")
                }

                Section {
                    Button("Reset all data", role: .destructive) { confirmReset = true }
                } footer: {
                    Text("Ember stores everything on this device. No account, no cloud.")
                }

                Section("About") {
                    LabeledContent("Version", value: Bundle.main.appVersion)
                    Text("Ember gives general fitness guidance, not medical advice, diagnosis or treatment. Stop any exercise that causes pain.")
                        .font(.ember(13)).foregroundStyle(Theme.inkSoft)
                }
            }
            .scrollContentBackground(.hidden)
            .emberBackground()
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .confirmationDialog("Reset all data?", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("Delete everything", role: .destructive) {
                    store.resetAll()
                    Reminders.update(store.settings)
                }
            } message: {
                Text("This removes your workouts, feedback, activities and scans. It can't be undone.")
            }
            .alert("YouTube API key", isPresented: $showKeyHelp) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("1. Go to console.cloud.google.com and create a project.\n2. Enable \"YouTube Data API v3\".\n3. Create an API key (restrict it to iOS apps with Ember's bundle ID).\n4. Paste it here.")
            }
        }
    }
}

extension Bundle {
    var appVersion: String {
        let v = infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}

/// Local daily reminder.
enum Reminders {
    static let id = "ember.daily"

    static func update(_ settings: AppSettings) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        guard settings.reminderEnabled else { return }
        center.requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Got 10 minutes?"
            content.body = "A quick Ember workout is ready when you are."
            content.sound = .default
            var comps = DateComponents()
            comps.hour = settings.reminderHour
            comps.minute = settings.reminderMinute
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }
}
