import SwiftUI

// MARK: - Backgrounds & cards

struct EmberBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    Theme.background
                    Theme.warmGlow
                }
                .ignoresSafeArea()
            }
    }
}

struct CardModifier: ViewModifier {
    var padding: CGFloat = 16
    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).stroke(Theme.line, lineWidth: 1))
            .shadow(color: Color.black.opacity(0.04), radius: 12, y: 6)
    }
}

extension View {
    func emberBackground() -> some View { modifier(EmberBackground()) }
    func emberCard(padding: CGFloat = 16) -> some View { modifier(CardModifier(padding: padding)) }
}

// MARK: - Buttons

struct EmberButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, ghost, danger }
    var kind: Kind = .primary
    var compact = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.ember(compact ? 15 : 17, .semibold))
            .padding(.vertical, compact ? 10 : 16)
            .padding(.horizontal, compact ? 16 : 20)
            .frame(maxWidth: compact ? nil : .infinity)
            .foregroundStyle(foreground)
            .background(background)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(border, lineWidth: kind == .secondary ? 1.5 : 0))
            .shadow(color: kind == .primary ? Theme.ember.opacity(0.35) : .clear, radius: 14, y: 8)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }

    private var foreground: Color {
        switch kind {
        case .primary, .danger: return .white
        case .secondary: return Theme.ember
        case .ghost: return Theme.inkSoft
        }
    }

    @ViewBuilder private var background: some View {
        switch kind {
        case .primary: Theme.emberGradient
        case .secondary: Theme.surface
        case .ghost: Color.clear
        case .danger: Color.red.opacity(0.85)
        }
    }

    private var border: Color { kind == .secondary ? Theme.ember.opacity(0.6) : .clear }
}

extension ButtonStyle where Self == EmberButtonStyle {
    static var emberPrimary: EmberButtonStyle { EmberButtonStyle(kind: .primary) }
    static var emberSecondary: EmberButtonStyle { EmberButtonStyle(kind: .secondary) }
    static var emberGhost: EmberButtonStyle { EmberButtonStyle(kind: .ghost) }
}

/// Subtle press feedback for tappable cards.
struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.92 : 1)
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

// MARK: - Chips

struct Chip: View {
    var title: String
    var symbol: String? = nil
    var isOn: Bool
    var tint: Color = Theme.ember
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: 13, weight: .semibold)) }
                Text(title).font(.ember(15, .medium))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .foregroundStyle(isOn ? Color.white : Theme.ink)
            .background(isOn ? AnyShapeStyle(tint) : AnyShapeStyle(Theme.surfaceMuted), in: Capsule())
            .overlay(Capsule().stroke(isOn ? Color.clear : Theme.line, lineWidth: 1))
        }
        .buttonStyle(PressableStyle())
        .sensoryFeedback(.selection, trigger: isOn)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// Simple wrapping layout for chips.
struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0, widest: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                y += rowHeight + spacing
                x = 0
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: proposal.width ?? widest, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                y += rowHeight + spacing
                x = bounds.minX
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

// MARK: - Headers, stats, rings

struct SectionHeader: View {
    var title: String
    var subtitle: String? = nil
    var trailing: AnyView? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.ember(20, .bold)).foregroundStyle(Theme.ink)
                if let subtitle { Text(subtitle).font(.ember(14)).foregroundStyle(Theme.inkSoft) }
            }
            Spacer()
            if let trailing { trailing }
        }
    }
}

struct StatTile: View {
    var value: String
    var label: String
    var symbol: String
    var tint: Color = Theme.ember

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 32, height: 32)
                .background(tint.opacity(0.12), in: Circle())
            Text(value).font(.ember(24, .bold)).foregroundStyle(Theme.ink).monospacedDigit()
                .contentTransition(.numericText())
            Text(label).font(.ember(13)).foregroundStyle(Theme.inkSoft)
        }
        .emberCard(padding: 14)
    }
}

struct RingProgress: View {
    var progress: Double
    var lineWidth: CGFloat = 12
    var tint: AnyShapeStyle = AnyShapeStyle(Theme.emberGradient)
    var track: Color = Theme.line

    var body: some View {
        ZStack {
            Circle().stroke(track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, progress)))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

struct LevelDots: View {
    var level: Int
    var tint: Color = Theme.ember
    var body: some View {
        HStack(spacing: 3) {
            ForEach(1...5, id: \.self) { i in
                Capsule().fill(i <= level ? tint : Theme.line).frame(width: 10, height: 5)
            }
        }
        .accessibilityLabel("Level \(level) of 5")
    }
}

struct InfoBanner: View {
    var text: String
    var symbol: String = "info.circle.fill"
    var tint: Color = Theme.calm

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tint)
            Text(text).font(.ember(14)).foregroundStyle(Theme.ink).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(tint.opacity(0.1), in: RoundedRectangle(cornerRadius: Theme.radiusSmall, style: .continuous))
    }
}

// MARK: - Formatting

enum Fmt {
    static func clock(_ seconds: Int) -> String {
        String(format: "%d:%02d", seconds / 60, seconds % 60)
    }

    static func minutes(_ seconds: Int) -> String {
        let m = Int((Double(seconds) / 60).rounded())
        return "\(max(1, m)) min"
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE d MMM"
        return f
    }()

    static func relativeDay(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date) { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        return dayFormatter.string(from: date)
    }

    static func time(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}
