import SwiftUI

/// Quick Setup (proposal §2.1): feeling + duration, with optional "More" for place, discomfort and categories.
struct SetupView: View {
    @Environment(EmberStore.self) private var store
    @Environment(AppRouter.self) private var router

    @State private var input = SetupInput()
    @State private var duration: Double = 10
    @State private var showMore = false
    @State private var loaded = false

    private let generator = WorkoutGenerator()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                if !input.focus.isEmpty || !input.preferredExercises.isEmpty { focusBanner }
                feelingSection
                durationSection
                moreSection
            }
            .padding(20)
            .padding(.bottom, 100)
        }
        .scrollIndicators(.hidden)
        .emberBackground()
        .navigationTitle("Setup")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { bottomBar }
        .onAppear(perform: load)
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        input = router.setupPrefill ?? store.suggestedSetup()
        router.setupPrefill = nil
        duration = Double(input.duration)
        showMore = !input.discomfort.isEmpty || input.location != .home || !input.disabledCategories.isEmpty
    }

    // MARK: Sections

    private var focusBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "figure.stand").foregroundStyle(Theme.calm)
            VStack(alignment: .leading, spacing: 2) {
                Text("Tuned by your body scan").font(.ember(15, .semibold)).foregroundStyle(Theme.ink)
                Text(input.focus.isEmpty ? "Recommended moves are preferred."
                     : "Extra " + input.focus.map { $0.title.lowercased() }.joined(separator: " & ") + ", recommended moves preferred.")
                    .font(.ember(13)).foregroundStyle(Theme.inkSoft)
            }
            Spacer()
            Button {
                withAnimation { input.focus = []; input.preferredExercises = [] }
            } label: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(Theme.inkSoft)
            }
            .accessibilityLabel("Remove scan focus")
        }
        .padding(14)
        .background(Theme.calm.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
    }

    private var feelingSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("How are you feeling today?").font(.ember(24, .bold)).foregroundStyle(Theme.ink)
            VStack(spacing: 8) {
                ForEach(Feeling.allCases) { feeling in
                    let selected = input.feeling == feeling
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { input.feeling = feeling }
                    } label: {
                        HStack(spacing: 14) {
                            Text(feeling.emoji).font(.system(size: 24))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(feeling.title).font(.ember(17, .semibold))
                                Text(feeling.subtitle).font(.ember(13)).opacity(0.75)
                            }
                            Spacer()
                            if selected {
                                Image(systemName: "checkmark.circle.fill").font(.system(size: 20))
                                    .transition(.scale.combined(with: .opacity))
                            }
                        }
                        .foregroundStyle(selected ? Color.white : Theme.ink)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                        .background {
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .fill(selected ? AnyShapeStyle(Theme.emberGradient) : AnyShapeStyle(Theme.surface))
                        }
                        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(selected ? Color.clear : Theme.line))
                    }
                    .buttonStyle(PressableStyle())
                    .sensoryFeedback(.selection, trigger: selected)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            if let fb = store.lastFeedback, fb.rating != .aboutRight {
                Label(fb.rating == .tooHard ? "Eased one level after last time's \"too hard\"."
                                             : "Bumped one level after last time's \"too easy\".",
                      systemImage: "arrow.triangle.2.circlepath")
                    .font(.ember(13))
                    .foregroundStyle(Theme.inkSoft)
            }
        }
    }

    private var durationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Duration").font(.ember(18, .bold)).foregroundStyle(Theme.ink)
                Spacer()
                Text("\(Int(duration))").font(.ember(40, .bold)).foregroundStyle(Theme.ember).monospacedDigit()
                    .contentTransition(.numericText())
                Text("min").font(.ember(17, .semibold)).foregroundStyle(Theme.inkSoft)
            }
            Slider(value: $duration, in: 5...30, step: 1) {
                Text("Duration")
            } minimumValueLabel: {
                Text("5").font(.ember(13)).foregroundStyle(Theme.inkSoft)
            } maximumValueLabel: {
                Text("30").font(.ember(13)).foregroundStyle(Theme.inkSoft)
            }
            .tint(Theme.ember)
            .sensoryFeedback(.selection, trigger: Int(duration))
            HStack(spacing: 8) {
                ForEach([5, 10, 15, 20, 30], id: \.self) { m in
                    Chip(title: "\(m)", isOn: Int(duration) == m) {
                        withAnimation { duration = Double(m) }
                    }
                }
            }
        }
        .emberCard()
    }

    private var moreSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) { showMore.toggle() }
            } label: {
                HStack {
                    Text("More").font(.ember(18, .bold)).foregroundStyle(Theme.ink)
                    Text("optional").font(.ember(13)).foregroundStyle(Theme.inkSoft)
                    Spacer()
                    Image(systemName: "chevron.down")
                        .rotationEffect(.degrees(showMore ? 180 : 0))
                        .foregroundStyle(Theme.inkSoft)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if showMore {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Where are you?").font(.ember(15, .semibold)).foregroundStyle(Theme.ink)
                        FlowLayout {
                            ForEach(Location.allCases) { place in
                                Chip(title: place.title, symbol: place.symbol, isOn: input.location == place) {
                                    input.location = place
                                }
                            }
                        }
                        Text(input.location.detail)
                            .font(.ember(12)).foregroundStyle(Theme.inkSoft)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Any discomfort?").font(.ember(15, .semibold)).foregroundStyle(Theme.ink)
                        FlowLayout {
                            ForEach(BodyArea.allCases) { area in
                                Chip(title: area.title, isOn: input.discomfort.contains(area), tint: Theme.warn) {
                                    if input.discomfort.contains(area) { input.discomfort.remove(area) } else { input.discomfort.insert(area) }
                                }
                            }
                        }
                        Text("Ember avoids moves that load these areas and adds an optional 60s ease at the end. This isn't medical advice.")
                            .font(.ember(12)).foregroundStyle(Theme.inkSoft)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Include").font(.ember(15, .semibold)).foregroundStyle(Theme.ink)
                        FlowLayout {
                            ForEach(MovementCategory.allCases) { cat in
                                let on = !input.disabledCategories.contains(cat)
                                Chip(title: cat.title, isOn: on, tint: Theme.color(for: cat)) {
                                    if on {
                                        if input.disabledCategories.count < MovementCategory.allCases.count - 1 {
                                            input.disabledCategories.insert(cat)
                                        }
                                    } else {
                                        input.disabledCategories.remove(cat)
                                    }
                                }
                            }
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .emberCard()
    }

    private var bottomBar: some View {
        VStack(spacing: 0) {
            Button {
                input.duration = Int(duration)
                let plan = generator.generate(input)
                store.rememberSetup(input)
                router.homePath.append(.plan(plan))
            } label: {
                Label("See my workout", systemImage: "sparkles")
            }
            .buttonStyle(.emberPrimary)
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 8)
        }
        .background(.ultraThinMaterial)
    }
}
