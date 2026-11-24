import SwiftUI

/// Log an activity done outside Ember (gym, tennis, swim…), or edit one.
struct AddActivityView: View {
    let existing: Activity?
    @Environment(EmberStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    @State private var kind: ActivityKind = .gym
    @State private var customKind = ""
    @State private var title = ""
    @State private var minutes = 45
    @State private var date = Date()
    @State private var effort = 3
    @State private var notes = ""
    @State private var loaded = false

    private let columns = [GridItem(.adaptive(minimum: 84), spacing: 10)]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    kindGrid
                    if kind == .other {
                        field("Activity type", text: $customKind, prompt: "e.g. Pilates, Rowing")
                    }
                    field("Name (optional)", text: $title, prompt: kind == .other ? "My activity" : kind.title)
                    durationCard
                    VStack(alignment: .leading, spacing: 10) {
                        Text("How hard was it?").font(.ember(16, .semibold)).foregroundStyle(Theme.ink)
                        HStack(spacing: 8) {
                            ForEach(1...5, id: \.self) { e in
                                Chip(title: ["Easy", "Light", "Moderate", "Hard", "Max"][e - 1], isOn: effort == e) { effort = e }
                            }
                        }
                    }
                    DatePicker("When", selection: $date, in: ...Date())
                        .font(.ember(16, .semibold))
                        .emberCard()
                    field("Notes", text: $notes, prompt: "Anything to remember?")
                    if existing != nil {
                        Button(role: .destructive) {
                            if let existing { store.delete(activityID: existing.id) }
                            dismiss()
                        } label: { Label("Delete activity", systemImage: "trash") }
                        .buttonStyle(EmberButtonStyle(kind: .danger))
                    }
                }
                .padding(20)
            }
            .emberBackground()
            .navigationTitle(existing == nil ? "Add activity" : "Edit activity")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save).fontWeight(.bold)
                        .disabled(kind == .other && customKind.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear(perform: load)
        }
    }

    private var kindGrid: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(ActivityKind.external) { k in
                let selected = kind == k
                Button { withAnimation(.snappy) { kind = k } } label: {
                    VStack(spacing: 6) {
                        Image(systemName: k.symbol).font(.system(size: 22, weight: .semibold))
                        Text(k.title).font(.ember(12, .medium)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 74)
                    .foregroundStyle(selected ? Color.white : Theme.ink)
                    .background {
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(selected ? AnyShapeStyle(Theme.calm) : AnyShapeStyle(Theme.surface))
                    }
                    .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(selected ? Color.clear : Theme.line))
                }
                .buttonStyle(PressableStyle())
            }
        }
    }

    private var durationCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Duration").font(.ember(16, .semibold)).foregroundStyle(Theme.ink)
                Spacer()
                Text("\(minutes) min").font(.ember(22, .bold)).foregroundStyle(Theme.calm).monospacedDigit()
            }
            Slider(value: Binding(get: { Double(minutes) }, set: { minutes = Int($0) }), in: 5...240, step: 5)
                .tint(Theme.calm)
        }
        .emberCard()
    }

    private func field(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.ember(16, .semibold)).foregroundStyle(Theme.ink)
            TextField(prompt, text: text)
                .font(.ember(16))
                .padding(12)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Theme.line))
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let a = existing else { return }
        kind = a.kind == .emberWorkout ? .other : a.kind
        customKind = a.customKind ?? ""
        title = a.title
        minutes = a.minutes
        date = a.date
        effort = a.effort ?? 3
        notes = a.notes ?? ""
    }

    private func save() {
        let trimmedTitle = title.trimmingCharacters(in: .whitespaces)
        let custom = customKind.trimmingCharacters(in: .whitespaces)
        let fallbackTitle = kind == .other ? (custom.isEmpty ? "Activity" : custom) : kind.title
        var activity = existing ?? Activity(date: date, title: "", minutes: minutes, kind: kind, origin: .external)
        activity.date = date
        activity.title = trimmedTitle.isEmpty ? fallbackTitle : trimmedTitle
        activity.minutes = minutes
        activity.kind = kind
        activity.customKind = kind == .other ? custom : nil
        activity.effort = effort
        activity.notes = notes.isEmpty ? nil : notes
        if existing == nil { store.add(activity: activity) } else { store.update(activity: activity) }
        dismiss()
    }
}
