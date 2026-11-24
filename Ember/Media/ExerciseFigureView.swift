import SwiftUI

/// Animated, offline illustration of an exercise.
struct ExerciseFigureView: View {
    var motion: MotionKind
    var tint: Color = Theme.ember
    var animated = true
    var showsGround = true
    var speed: Double = 1

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let m = FigureMotion.motion(for: motion)
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !animated || reduceMotion)) { timeline in
            let t = (animated && !reduceMotion) ? timeline.date.timeIntervalSinceReferenceDate * speed : m.cycle * 0.25
            Canvas { context, size in
                draw(m.pose(at: t), motion: m, in: &context, size: size)
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func draw(_ pose: FigurePose, motion: FigureMotion, in ctx: inout GraphicsContext, size: CGSize) {
        let s = min(size.width, size.height)
        let ox = (size.width - s) / 2, oy = (size.height - s) / 2
        func p(_ q: CGPoint) -> CGPoint { CGPoint(x: ox + q.x * s, y: oy + q.y * s) }

        let propColor = Theme.inkSoft.opacity(0.35)
        if showsGround {
            var ground = Path()
            ground.move(to: p(CGPoint(x: 0.06, y: FigureMotion.ground)))
            ground.addLine(to: p(CGPoint(x: 0.94, y: FigureMotion.ground)))
            ctx.stroke(ground, with: .color(propColor), style: StrokeStyle(lineWidth: s * 0.012, lineCap: .round))
        }
        for prop in motion.props {
            switch prop {
            case .rect(let r):
                let rect = CGRect(origin: p(r.origin), size: CGSize(width: r.width * s, height: r.height * s))
                ctx.stroke(Path(roundedRect: rect, cornerRadius: s * 0.012), with: .color(propColor), lineWidth: s * 0.012)
            case .line(let a, let b):
                var path = Path()
                path.move(to: p(a))
                path.addLine(to: p(b))
                ctx.stroke(path, with: .color(propColor), style: StrokeStyle(lineWidth: s * 0.014, lineCap: .round))
            }
        }

        let j = pose.joints
        let width = s * 0.045
        let style = StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
        let far = GraphicsContext.Shading.color(tint.opacity(0.42))
        let near = GraphicsContext.Shading.color(tint)

        func limb(_ pts: [CGPoint], _ shading: GraphicsContext.Shading) {
            var path = Path()
            path.addLines(pts.map(p))
            ctx.stroke(path, with: shading, style: style)
        }

        // Far side first.
        limb([j.hipF, j.kneeF, j.footF], far)
        limb([j.shoulderF, j.elbowF, j.handF], far)
        // Body
        limb([j.hipF, j.hipN], near)
        limb([j.hip, j.shoulderC, j.neck], near)
        limb([j.shoulderF, j.shoulderN], near)
        // Near side
        limb([j.hipN, j.kneeN, j.footN], near)
        limb([j.shoulderN, j.elbowN, j.handN], near)

        let r = FigureLengths.head * s
        let c = p(j.head)
        ctx.fill(Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: r * 2, height: r * 2)), with: near)
    }
}

/// Rounded tile with the figure on a soft background — used in lists.
struct ExerciseThumb: View {
    var exercise: Exercise
    var size: CGFloat = 56
    var animated = false

    var body: some View {
        let tint = Theme.color(for: exercise.category)
        ExerciseFigureView(motion: exercise.motion, tint: tint, animated: animated)
            .padding(size * 0.06)
            .frame(width: size, height: size)
            .background(tint.opacity(0.10), in: RoundedRectangle(cornerRadius: size * 0.28, style: .continuous))
    }
}
