import SwiftUI

/// Activity Log (proposal §2.5): in-app sessions and outside activities together, newest first.
struct LogView: View {
    @Environment(EmberStore.self) private var store
    @State private var mode = 0
    @State private var showAdd = false
    @State private var editing: Activity?
    @State private var viewingSession: Session?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("View", selection: $mode) {
                    Text("History").tag(0)
                    Text("Insights").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 20)
                .padding(.vertical, 8)

                if mode == 0 { history } else { InsightsView() }
            }
            .emberBackground()
            .navigationTitle("Activity")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAdd = true } label: { Label("Add activity", systemImage: "plus.circle.fill") }
                }
            }
            .sheet(isPresented: $showAdd) { AddActivityView(existing: nil) }
            .sheet(item: $editing) { activity in AddActivityView(existing: activity) }
            .sheet(item: $viewingSession) { session in SessionDetailView(session: session) }
        }
    }

    private struct DayGroup: Identifiable {
        let day: Date
        let items: [Activity]
        var id: Date { day }
    }

    private var grouped: [DayGroup] {
        let cal = Calendar.current
        let groups = Dictionary(grouping: store.activities) { cal.startOfDay(for: $0.date) }
        return groups.keys.sorted(by: >).map { day in
            DayGroup(day: day, items: (groups[day] ?? []).sorted { $0.date > $1.date })
        }
    }

    @ViewBuilder private var history: some View {
        if store.activities.isEmpty {
            ContentUnavailableView {
                Label("Nothing logged yet", systemImage: "flame")
            } description: {
                Text("Finish an Ember workout, or add a gym session, a tennis match or a swim to keep everything in one place.")
            } actions: {
                Button("Add an outside activity") { showAdd = true }
                    .buttonStyle(EmberButtonStyle(kind: .primary, compact: true))
            }
            .frame(maxHeight: .infinity)
        } else {
            List {
                ForEach(grouped) { group in
                    Section {
                        ForEach(group.items) { activity in
                            Button {
                                if activity.origin == .inApp, let s = store.session(id: activity.sessionID) {
                                    viewingSession = s
                                } else {
                                    editing = activity
                                }
                            } label: {
                                ActivityRow(activity: activity)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Theme.surface)
                            .swipeActions {
                                Button(role: .destructive) { store.delete(activityID: activity.id) } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    } header: {
                        HStack {
                            Text(Fmt.relativeDay(group.day))
                            Spacer()
                            Text("\(group.items.reduce(0) { $0 + $1.minutes }) min")
                        }
                        .font(.ember(13, .semibold))
                        .foregroundStyle(Theme.inkSoft)
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .listStyle(.insetGrouped)
        }
    }
}

struct ActivityRow: View {
    let activity: Activity

    private var tint: Color { activity.origin == .inApp ? Theme.ember : Theme.calm }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: activity.kind.symbol)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(activity.origin == .inApp ? Color.white : tint)
                .frame(width: 42, height: 42)
                .background {
                    if activity.origin == .inApp {
                        Circle().fill(Theme.emberGradient)
                    } else {
                        Circle().fill(tint.opacity(0.12))
                    }
                }
            VStack(alignment: .leading, spacing: 3) {
                Text(activity.title).font(.ember(16, .semibold)).foregroundStyle(Theme.ink).lineLimit(1)
                HStack(spacing: 6) {
                    Text(activity.origin == .inApp ? "Ember" : activity.displayKind)
                    Text("·")
                    Text(Fmt.time(activity.date))
                    if let notes = activity.notes, !notes.isEmpty {
                        Text("·")
                        Text(notes).lineLimit(1)
                    }
                }
                .font(.ember(13))
                .foregroundStyle(Theme.inkSoft)
            }
            Spacer(minLength: 4)
            Text("\(activity.minutes) min")
                .font(.ember(15, .bold))
                .foregroundStyle(Theme.ink)
                .monospacedDigit()
        }
        .padding(.vertical, 6)
        .contentShape(Rectangle())
    }
}

/// Details of an in-app session.
struct SessionDetailView: View {
    let session: Session
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Feeling", value: session.input.feeling.title)
                    LabeledContent("Planned", value: "\(session.input.duration) min")
                    LabeledContent("Actual", value: Fmt.clock(session.elapsedSeconds))
                    LabeledContent("Place", value: session.input.location.title)
                    if !session.input.discomfort.isEmpty {
                        LabeledContent("Discomfort", value: session.input.discomfort.sorted().map(\.title).joined(separator: ", "))
                    }
                    LabeledContent("Breaks skipped", value: "\(session.skippedBreaks)")
                    LabeledContent("Breaks extended", value: "\(session.extendedBreaks)")
                }
                Section("Exercises") {
                    ForEach(Array(session.results.enumerated()), id: \.offset) { _, r in
                        if let ex = ExerciseLibrary.exercise(r.exerciseID) {
                            HStack(spacing: 12) {
                                ExerciseThumb(exercise: ex, size: 40)
                                VStack(alignment: .leading) {
                                    Text(ex.name).font(.ember(15, .semibold))
                                    Text(r.status == .completed ? "Completed · \(r.activeSeconds)s" : "Skipped")
                                        .font(.ember(12))
                                        .foregroundStyle(r.status == .completed ? Theme.good : Theme.inkSoft)
                                }
                                Spacer()
                                Image(systemName: r.status == .completed ? "checkmark.circle.fill" : "forward.circle")
                                    .foregroundStyle(r.status == .completed ? Theme.good : Theme.inkSoft)
                            }
                        }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .emberBackground()
            .navigationTitle(Fmt.relativeDay(session.startedAt) + " · " + Fmt.time(session.startedAt))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}
