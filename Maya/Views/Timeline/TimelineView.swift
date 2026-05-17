import AVFoundation
import AppKit
import CoreMedia
import SwiftUI

struct TimelineView: View {
    @Bindable var project: Project
    let onSelectSegment: (ZoomSegment) -> Void

    @State private var isScrubbing: Bool = false

    private let rowLabelWidth: CGFloat = 96
    private let rulerHeight: CGFloat = 20
    private let animationsHeight: CGFloat = 60
    private let videoHeight: CGFloat = 56
    private let thumbnailCount: Int = 18

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                rowLabels
                tracks
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.black.opacity(0.35))
    }

    private var rowLabels: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Space matching the ruler row
            Color.clear.frame(height: rulerHeight)

            HStack(spacing: 6) {
                Image(systemName: "sparkles")
                Text("Animations")
                    .font(.callout.weight(.semibold))
            }
            .foregroundStyle(.white.opacity(0.85))
            .frame(height: animationsHeight, alignment: .center)

            HStack(spacing: 6) {
                Image(systemName: "iphone")
                Text(project.deviceFrame.displayName)
                    .font(.callout.weight(.semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .foregroundStyle(.white.opacity(0.85))
            .frame(height: videoHeight, alignment: .center)
        }
        .frame(width: rowLabelWidth, alignment: .leading)
    }

    private var tracks: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let duration = project.durationSeconds
            let totalHeight = rulerHeight + animationsHeight + videoHeight + 8

            ZStack(alignment: .topLeading) {
                VStack(spacing: 4) {
                    TimeRuler(duration: duration, width: width, height: rulerHeight)
                    AnimationsTrack(
                        project: project,
                        height: animationsHeight,
                        onSelectSegment: onSelectSegment
                    )
                    if let url = project.videoURL {
                        VideoThumbnailStrip(
                            url: url,
                            thumbnailCount: thumbnailCount,
                            height: videoHeight
                        )
                    } else {
                        RoundedRectangle(cornerRadius: 6)
                            .fill(Color.white.opacity(0.05))
                            .frame(height: videoHeight)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .local) { point in
                    if duration > 0 {
                        let t = max(0, min(Double(point.x / width) * duration, duration))
                        seek(to: t)
                    }
                }

                // Draggable playhead with time tooltip
                if duration > 0 {
                    let x = CGFloat(project.currentSeconds / duration) * width
                    Playhead(
                        height: totalHeight,
                        timeText: isScrubbing ? formatTimestamp(project.currentSeconds) : nil
                    )
                    .position(x: x, y: totalHeight / 2)
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named("tracksSpace"))
                            .onChanged { v in
                                guard duration > 0 else { return }
                                isScrubbing = true
                                let t = max(0, min(Double(v.location.x / width) * duration, duration))
                                project.seek(to: t)
                            }
                            .onEnded { _ in isScrubbing = false }
                    )
                }
            }
            .coordinateSpace(name: "tracksSpace")
        }
        .frame(height: rulerHeight + animationsHeight + videoHeight + 8)
    }

    private func seek(to seconds: Double) {
        guard let player = project.player else { return }
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        project.currentSeconds = seconds
    }
}

private struct TimeRuler: View {
    let duration: Double
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        Canvas { ctx, size in
            guard duration > 0 else { return }
            let interval = tickInterval(duration: duration)
            var t = 0.0
            while t <= duration {
                let x = CGFloat(t / duration) * size.width
                var path = Path()
                path.move(to: CGPoint(x: x, y: size.height - 6))
                path.addLine(to: CGPoint(x: x, y: size.height))
                ctx.stroke(path, with: .color(.white.opacity(0.5)), lineWidth: 1)

                let label = format(time: t)
                ctx.draw(
                    Text(label)
                        .font(.system(size: 9, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.7)),
                    at: CGPoint(x: x, y: 4),
                    anchor: .top
                )
                t += interval
            }
        }
        .frame(width: width, height: height)
    }

    private func tickInterval(duration: Double) -> Double {
        switch duration {
        case ..<10: 1
        case ..<30: 2
        case ..<90: 5
        case ..<300: 15
        default: 30
        }
    }

    private func format(time t: Double) -> String {
        let total = Int(t.rounded())
        let m = total / 60
        let s = total % 60
        return String(format: "%d:%02d", m, s)
    }
}

private struct Playhead: View {
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

            // Wider invisible grab zone for the drag gesture
            Color.white.opacity(0.001)
                .frame(width: 18, height: height)

            if let text = timeText {
                TimeTooltip(text: text)
                    .offset(y: -(height / 2) - 14)
                    .allowsHitTesting(false)
            }
        }
        .contentShape(Rectangle())
    }
}
