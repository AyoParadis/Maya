import SwiftUI

struct TimelineRuler: View {
    let duration: Double
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Canvas { ctx, size in
            guard duration > 0 else { return }
            let major = majorInterval(duration: duration)
            let minor = major / 4

            var t = 0.0
            while t <= duration {
                let x = CGFloat(t / duration) * size.width
                if !nearlyMultiple(t, of: major) {
                    var path = Path()
                    path.move(to: CGPoint(x: x, y: size.height - 3))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    ctx.stroke(path, with: .color(.white.opacity(0.22)), lineWidth: 1)
                }
                t += minor
            }

            t = 0.0
            while t <= duration {
                let x = CGFloat(t / duration) * size.width
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height - 6))
                path.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(path, with: .color(.white.opacity(0.55)), lineWidth: 1)

                ctx.draw(
                    Text(format(time: t))
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.75)),
                    at: CGPoint(x: x, y: 4),
                    anchor: .top
                )
                t += major
            }
        }
        .frame(width: width, height: height)
    }

    private func majorInterval(duration: Double) -> Double {
        switch duration {
        case ..<10: 1
        case ..<30: 2
        case ..<90: 5
        case ..<300: 15
        default: 30
        }
    }

    private func nearlyMultiple(_ t: Double, of step: Double) -> Bool {
        guard step > 0 else { return false }
        let r = t.truncatingRemainder(dividingBy: step)
        return r < 0.001 || abs(r - step) < 0.001
    }

    private func format(time t: Double) -> String {
        let total = Int(t.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

struct TimelinePlayhead: View {
    let height: CGFloat
    let timeText: String?

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                Capsule()
                    .fill(.white)
                    .frame(width: 12, height: 12)
                Rectangle()
                    .fill(.white.opacity(0.85))
                    .frame(width: 2, height: height - 12)
            }
            .shadow(color: .black.opacity(0.4), radius: 2, y: 1)
            .allowsHitTesting(false)

            Color.white.opacity(0.001)
                .frame(width: 18, height: height)

            if let timeText {
                TimeTooltip(text: timeText)
                    .offset(y: -(height / 2) - 14)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
    }
}
