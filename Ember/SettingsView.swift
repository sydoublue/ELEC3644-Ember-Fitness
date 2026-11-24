import SwiftUI

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @State private var confirmReset = false

    var body: some View {
        List {
            Section("This prototype") {
                Text("Apple Watch and HealthKit are not connected.")
                Text("Workouts and the log stay on this phone. There is no account.")
                Text("Form Check uses the camera during a workout. The picture stays on this phone and is not saved.")
            }
            Section {
                Button("Reset on-device data", role: .destructive) {
                    confirmReset = true
                }
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.inline)
        .confirmationDialog("Reset everything saved on this phone?", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("Reset", role: .destructive) { store.reset() }
            Button("Cancel", role: .cancel) {}
        }
    }
}
