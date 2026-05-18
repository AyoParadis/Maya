import CoreGraphics
import Foundation

enum ZoomFocus: String, Hashable, Sendable, CaseIterable, Identifiable {
    case top, center, bottom

    var id: String { rawValue }

    var label: String {
        switch self {
        case .top: "Top"
        case .center: "Center"
        case .bottom: "Bottom"
        }
    }

    var systemImage: String {
        switch self {
        case .top: "arrow.up.to.line.compact"
        case .center: "scope"
        case .bottom: "arrow.down.to.line.compact"
        }
    }
}

enum AnimationCurve: String, Hashable, Sendable, CaseIterable, Identifiable {
    case spring   // back easing, ~12% overshoot
    case bouncy   // back easing, ~20% overshoot
    case smooth   // ease-in-out cubic, no overshoot
    case snappy   // ease-out quart, fast attack, slow settle
    case gentle   // ease-out sine, soft and organic
    case linear   // constant rate, mechanical

    var id: String { rawValue }

    var label: String {
        switch self {
        case .spring: "Spring"
        case .bouncy: "Bouncy"
        case .smooth: "Smooth"
        case .snappy: "Snappy"
        case .gentle: "Gentle"
        case .linear: "Linear"
        }
    }

    var symbol: String {
        switch self {
        case .spring: "waveform.path"
        case .bouncy: "tornado"
        case .smooth: "scribble.variable"
        case .snappy: "bolt.horizontal.fill"
        case .gentle: "wind"
        case .linear: "line.diagonal"
        }
    }

    var hint: String {
        switch self {
        case .spring: "Soft overshoot, lively"
        case .bouncy: "More overshoot, playful"
        case .smooth: "Classic ease in/out"
        case .snappy: "Fast attack, slow settle"
        case .gentle: "Soft and organic"
        case .linear: "Constant rate"
        }
    }
}

/// A timed zoom event on the timeline. Outside the segment the camera sits at its base
/// state (`Project.scale` / `Project.offset`). Inside, it ramps to the peak (`scale` +
/// `focus`) using `transitionIn` seconds, holds, then ramps back over `transitionOut`.
struct ZoomSegment: Identifiable, Hashable, Sendable {
    var id: UUID = UUID()
    var startTime: Double
    var duration: Double
    var scale: CGFloat
    var focus: ZoomFocus
    var transitionIn: Double
    var transitionOut: Double
    var curve: AnimationCurve

    static let defaultDuration: Double = 2.0
    static let defaultScale: CGFloat = 1.35
    static let defaultTransition: Double = 0.45
    static let defaultCurve: AnimationCurve = .spring

    static let durationRange: ClosedRange<Double> = 0.4...10.0
    static let scaleRange: ClosedRange<CGFloat> = 1.0...2.5
    static let transitionRange: ClosedRange<Double> = 0.05...2.0

    var endTime: Double { startTime + duration }

    init(
        id: UUID = UUID(),
        startTime: Double,
        duration: Double,
        scale: CGFloat,
        focus: ZoomFocus,
        transitionIn: Double = ZoomSegment.defaultTransition,
        transitionOut: Double = ZoomSegment.defaultTransition,
        curve: AnimationCurve = ZoomSegment.defaultCurve
    ) {
        self.id = id
        self.startTime = startTime
        self.duration = duration
        self.scale = scale
        self.focus = focus
        self.transitionIn = transitionIn
        self.transitionOut = transitionOut
        self.curve = curve
    }

    /// Clamps the transition durations so they always fit inside `duration` and
    /// stay within `transitionRange`. Call after mutating any of those fields.
    mutating func normalize() {
        duration = max(ZoomSegment.durationRange.lowerBound,
                       min(duration, ZoomSegment.durationRange.upperBound))
        let half = max(0.05, duration / 2)
        transitionIn = max(ZoomSegment.transitionRange.lowerBound,
                           min(transitionIn, half))
        transitionOut = max(ZoomSegment.transitionRange.lowerBound,
                            min(transitionOut, half))
    }

    struct Preset: Identifiable, Hashable, Sendable {
        let id: String
        let name: String
        let scale: CGFloat
        let focus: ZoomFocus
        let duration: Double
        let transitionIn: Double
        let transitionOut: Double
        let curve: AnimationCurve
        let previewName: String

        func makeSegment(at startTime: Double) -> ZoomSegment {
            ZoomSegment(
                startTime: startTime,
                duration: duration,
                scale: scale,
                focus: focus,
                transitionIn: transitionIn,
                transitionOut: transitionOut,
                curve: curve
            )
        }
    }

    static let presets: [Preset] = [
        Preset(id: "punch",    name: "Quick Punch",  scale: 1.45, focus: .center, duration: 1.2, transitionIn: 0.22, transitionOut: 0.22, curve: .snappy, previewName: "quick-punch"),
        Preset(id: "dramatic", name: "Dramatic",     scale: 1.8,  focus: .center, duration: 2.4, transitionIn: 0.55, transitionOut: 0.55, curve: .bouncy, previewName: "dramatic"),
        Preset(id: "topFocus", name: "Top Focus",    scale: 1.5,  focus: .top,    duration: 2.2, transitionIn: 0.45, transitionOut: 0.45, curve: .spring, previewName: "top-focus"),
        Preset(id: "botFocus", name: "Bottom Focus", scale: 1.5,  focus: .bottom, duration: 2.2, transitionIn: 0.45, transitionOut: 0.45, curve: .spring, previewName: "bottom-focus"),
        Preset(id: "soft",     name: "Soft Reveal",  scale: 1.25, focus: .center, duration: 2.6, transitionIn: 0.6,  transitionOut: 0.6,  curve: .gentle, previewName: "soft-reveal")
    ]

    /// Returns the preset whose timing/scale/focus/curve match the current segment, if any.
    /// Used to highlight the selected card and offer "Customize" for non-preset states.
    var matchingPreset: Preset? {
        ZoomSegment.presets.first { preset in
            abs(preset.scale - scale) < 0.001 &&
            preset.focus == focus &&
            abs(preset.duration - duration) < 0.001 &&
            abs(preset.transitionIn - transitionIn) < 0.001 &&
            abs(preset.transitionOut - transitionOut) < 0.001 &&
            preset.curve == curve
        }
    }

    mutating func apply(preset: Preset) {
        scale = preset.scale
        focus = preset.focus
        duration = preset.duration
        transitionIn = preset.transitionIn
        transitionOut = preset.transitionOut
        curve = preset.curve
        normalize()
    }
}
