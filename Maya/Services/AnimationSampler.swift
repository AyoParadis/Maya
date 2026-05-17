import CoreGraphics
import Foundation

struct AnimationSample: Equatable, Sendable {
    var scale: CGFloat
    var offsetX: CGFloat
    var offsetY: CGFloat
}

enum AnimationSampler {
    /// Natural phone occupies this fraction of the canvas side at scale 1.0.
    /// Must match `FramedDeviceView.naturalHeightFraction` so preview and export align.
    static let baseHeightFraction: CGFloat = 0.9

    /// Returns the effective camera state at a given time. The camera lives at its
    /// `base` state by default; if `seconds` falls inside an active segment, the state
    /// is eased between `base` and the segment's peak across the in/hold/out envelope
    /// using the segment's chosen curve.
    static func sample(
        at seconds: Double,
        segments: [ZoomSegment],
        baseScale: CGFloat,
        baseOffset: CGSize
    ) -> AnimationSample {
        let base = AnimationSample(
            scale: baseScale,
            offsetX: baseOffset.width,
            offsetY: baseOffset.height
        )

        guard let segment = segments.first(where: { seconds >= $0.startTime && seconds <= $0.endTime })
        else { return base }

        let localT = seconds - segment.startTime
        let half = max(0.05, segment.duration / 2)
        let envelope = envelopeProgress(
            localTime: localT,
            duration: segment.duration,
            transitionIn: min(segment.transitionIn, half),
            transitionOut: min(segment.transitionOut, half),
            curve: segment.curve
        )

        let peak = peakState(of: segment)
        return AnimationSample(
            scale: lerp(base.scale, peak.scale, CGFloat(envelope)),
            offsetX: lerp(base.offsetX, peak.offsetX, CGFloat(envelope)),
            offsetY: lerp(base.offsetY, peak.offsetY, CGFloat(envelope))
        )
    }

    /// Peak (held) state of a segment based on its scale + focus.
    private static func peakState(of segment: ZoomSegment) -> AnimationSample {
        let dy: CGFloat
        switch segment.focus {
        case .center: dy = 0
        case .top: dy = baseHeightFraction * (segment.scale - 1) / 2
        case .bottom: dy = -baseHeightFraction * (segment.scale - 1) / 2
        }
        return AnimationSample(scale: segment.scale, offsetX: 0, offsetY: dy)
    }

    /// Returns envelope progress: 0 = base, 1 = peak. May briefly overshoot above 1
    /// or undershoot below 0 depending on the chosen curve — that's the "spring" feel.
    private static func envelopeProgress(
        localTime t: Double,
        duration: Double,
        transitionIn: Double,
        transitionOut: Double,
        curve: AnimationCurve
    ) -> Double {
        guard duration > 0 else { return 0 }
        if t <= 0 { return 0 }
        if t >= duration { return 0 }

        let easeFn = easingFunction(for: curve)

        if t < transitionIn && transitionIn > 0 {
            return easeFn(t / transitionIn)
        }
        let outStart = duration - transitionOut
        if t >= outStart && transitionOut > 0 {
            return 1 - easeFn((t - outStart) / transitionOut)
        }
        return 1
    }

    // MARK: - Curves
    //
    // All curves accept u ∈ [0, 1] and return ~0 at u=0 and ~1 at u=1. Spring/Bouncy
    // briefly exceed 1 in the middle — that's intentional (overshoot).

    private static func easingFunction(for curve: AnimationCurve) -> (Double) -> Double {
        switch curve {
        case .spring: return { springOut($0, overshoot: 1.55) }
        case .bouncy: return { springOut($0, overshoot: 2.7) }
        case .smooth: return easeInOutCubic
        case .snappy: return easeOutQuart
        case .gentle: return easeOutSine
        case .linear: return { max(0, min(1, $0)) }
        }
    }

    /// Back-out easing (a.k.a. spring). Larger `overshoot` = more bounce.
    private static func springOut(_ u: Double, overshoot c1: Double) -> Double {
        let c3 = c1 + 1
        let t = max(0, min(1, u)) - 1
        return 1 + c3 * t * t * t + c1 * t * t
    }

    private static func easeInOutCubic(_ u: Double) -> Double {
        let c = max(0, min(1, u))
        return c < 0.5 ? 4 * c * c * c : 1 - pow(-2 * c + 2, 3) / 2
    }

    private static func easeOutQuart(_ u: Double) -> Double {
        let c = max(0, min(1, u))
        return 1 - pow(1 - c, 4)
    }

    private static func easeOutSine(_ u: Double) -> Double {
        let c = max(0, min(1, u))
        return sin((c * .pi) / 2)
    }

    private static func lerp(_ a: CGFloat, _ b: CGFloat, _ t: CGFloat) -> CGFloat {
        return a + (b - a) * t
    }
}
