import SwiftUI
import Charts

/// Charts over the shared log (the proposal's "future" charts, built now).
struct InsightsView: View {
    @Environment(EmberStore.self) private var store

    private struct CategoryCount: Identifiable {
        let category: MovementCategory
        let count: Int
        var id: String { category.rawValue }
    }

    private struct FeedbackPoint: Identifiable {
        let index: Int
        let date: Date
        let difficulty: Int
        let rating: DifficultyRating
        var id: Int { index }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                tiles
                weekChart
                categoryChart
                feedbackChart
                Text("Everything here is calculated on your phone from your own log.")
                    .font(.ember(12)).foregroundStyle(Theme.inkSoft)
                    .frame(maxWidth: .infinity)
            }
            .padding(20)
        }
        .scrollIndicators(.hidden)
    }

    private var tiles: some View {
        let total = store.activities.reduce(0) { $0 + $1.minutes }
        return LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            StatTile(value: "\(store.minutesThisWeek)", label: "min this week", symbol: "calendar", tint: Theme.ember)
            StatTile(value: "\(store.streakDays)", label: "day streak", symbol: "flame.fill", tint: Theme.amber)
            StatTile(value: "\(store.sessions.count)", label: "Ember sessions", symbol: "bolt.fill", tint: Theme.calm)
            StatTile(value: total >= 120 ? String(format: "%.1f h", Double(total) / 60) : "\(total) min",
                     label: "all time", symbol: "hourglass", tint: Theme.good)
        }
    }

    private var weekChart: some View {
        let days = store.dailyMinutes(lastDays: 7)
        return VStack(alignment: .leading, spacing: 12) {
            Text("Last 7 days").font(.ember(18, .bold)).foregroundStyle(Theme.ink)
            Chart {
                ForEach(days) { d in
                    BarMark(x: .value("Day", d.day, unit: .day), y: .value("Minutes", d.inApp))
                        .foregroundStyle(by: .value("Source", "Ember"))
                        .cornerRadius(5)
                    BarMark(x: .value("Day", d.day, unit: .day), y: .value("Minutes", d.external))
                        .foregroundStyle(by: .value("Source", "Outside"))
                        .cornerRadius(5)
                }
                if store.settings.weeklyGoalMinutes > 0 {
                    RuleMark(y: .value("Daily target", Double(store.settings.weeklyGoalMinutes) / 7))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                        .foregroundStyle(Theme.inkSoft)
                        .annotation(position: .top, alignment: .trailing) {
                            Text("daily target").font(.ember(10)).foregroundStyle(Theme.inkSoft)
                        }
                }
            }
            .chartForegroundStyleScale(["Ember": Theme.ember, "Outside": Theme.calm])
            .chartXAxis {
                AxisMarks(values: .stride(by: .day)) { _ in
                    AxisValueLabel(format: .dateTime.weekday(.narrow))
                }
            }
            .frame(height: 190)
        }
        .emberCard()
    }

    private var categoryCounts: [CategoryCount] {
        var counts: [MovementCategory: Int] = [:]
        for session in store.sessions {
            for r in session.results where r.status == .completed && !r.isRecovery {
                if let ex = ExerciseLibrary.exercise(r.exerciseID) { counts[ex.category, default: 0] += 1 }
            }
        }
        return MovementCategory.allCases.compactMap { c in
            guard let n = counts[c], n > 0 else { return nil }
            return CategoryCount(category: c, count: n)
        }
    }

    @ViewBuilder private var categoryChart: some View {
        let data = categoryCounts
        VStack(alignment: .leading, spacing: 12) {
            Text("What you've trained").font(.ember(18, .bold)).foregroundStyle(Theme.ink)
            if data.isEmpty {
                Text("Complete an Ember workout to see your balance across push, squat, hinge, core and mobility.")
                    .font(.ember(14)).foregroundStyle(Theme.inkSoft)
            } else {
                HStack(spacing: 18) {
                    Chart(data) { item in
                        SectorMark(angle: .value("Moves", item.count), innerRadius: .ratio(0.62), angularInset: 2)
                            .foregroundStyle(Theme.color(for: item.category))
                            .cornerRadius(4)
                    }
                    .frame(width: 130, height: 130)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(data) { item in
                            HStack(spacing: 8) {
                                Circle().fill(Theme.color(for: item.category)).frame(width: 10, height: 10)
                                Text(item.category.title).font(.ember(14)).foregroundStyle(Theme.ink)
                                Spacer()
                                Text("\(item.count)").font(.ember(14, .semibold)).foregroundStyle(Theme.inkSoft)
                            }
                        }
                    }
                }
            }
        }
        .emberCard()
    }

    private var feedbackPoints: [FeedbackPoint] {
        let sorted = store.feedbacks.sorted { $0.date < $1.date }.suffix(12)
        return sorted.enumerated().map { i, f in
            FeedbackPoint(index: i + 1, date: f.date, difficulty: f.difficultyUsed, rating: f.rating)
        }
    }

    @ViewBuilder private var feedbackChart: some View {
        let points = feedbackPoints
        VStack(alignment: .leading, spacing: 12) {
            Text("Difficulty over time").font(.ember(18, .bold)).foregroundStyle(Theme.ink)
            if points.count < 2 {
                Text("After a couple of workouts you'll see how your level adapts to your feedback.")
                    .font(.ember(14)).foregroundStyle(Theme.inkSoft)
            } else {
                Chart(points) { p in
                    LineMark(x: .value("Session", p.index), y: .value("Level", p.difficulty))
                        .interpolationMethod(.monotone)
                        .foregroundStyle(Theme.ember)
                    PointMark(x: .value("Session", p.index), y: .value("Level", p.difficulty))
                        .foregroundStyle(p.rating == .tooHard ? Theme.warn : (p.rating == .tooEasy ? Theme.calm : Theme.good))
                        .symbolSize(70)
                }
                .chartYScale(domain: 1...5)
                .chartYAxis {
                    AxisMarks(values: [1, 2, 3, 4, 5]) { value in
                        AxisGridLine()
                        AxisValueLabel {
                            if let v = value.as(Int.self) { Text(Feeling.from(difficulty: v).title).font(.ember(10)) }
                        }
                    }
                }
                .frame(height: 170)
                HStack(spacing: 14) {
                    legend("Too easy", Theme.calm)
                    legend("About right", Theme.good)
                    legend("Too hard", Theme.warn)
                }
            }
        }
        .emberCard()
    }

    private func legend(_ text: String, _ color: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(text).font(.ember(12)).foregroundStyle(Theme.inkSoft)
        }
    }
}
