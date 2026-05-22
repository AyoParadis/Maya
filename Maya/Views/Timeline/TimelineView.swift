import AVFoundation
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
            TimelineToolbar(project: project)
            Divider().opacity(0.4)
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

            TimelineRowLabel(icon: "sparkles", title: "Animations", height: animationsHeight)

            TimelineRowLabel(icon: "iphone", title: project.deviceFrame.displayName, height: videoHeight)
        }
        .frame(width: rowLabelWidth, alignment: .leading)
    }

    private var tracks: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let duration = project.timelineDuration
            let totalHeight = rulerHeight + animationsHeight + videoHeight + 8

            ZStack(alignment: .topLeading) {
                VStack(spacing: 4) {
                    TimelineRuler(duration: duration, width: width, height: rulerHeight)
                    AnimationsTrack(
                        project: project,
                        height: animationsHeight,
                        onSelectSegment: onSelectSegment
                    )
                    TrimmableVideoClip(
                        project: project,
                        height: videoHeight,
                        thumbnailCount: thumbnailCount
                    )
                }
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .local) { point in
                    if duration > 0 {
                        let raw = Double(point.x / width) * duration
                        project.seek(to: raw)
                    }
                }

                // Draggable playhead with time tooltip. Position is in timeline coords.
                if duration > 0 {
                    let x = CGFloat(project.currentSeconds / duration) * width
                    TimelinePlayhead(
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

}

/// Compact transport bar above the tracks. Play/pause, current time, total/trimmed duration,
/// trim badge with reset, and volume controls. Kept slim so the timeline still has room.
private struct TimelineToolbar: View {
    @Bindable var project: Project

    var body: some View {
        HStack(spacing: 12) {
            TimelineToolbarIconButton(
                systemImage: project.player?.timeControlStatus == .playing ? "pause.fill" : "play.fill",
                help: "Play/Pause (space)",
                action: project.togglePlayback
            )

            TimelineTimeReadout(current: project.currentSeconds, total: displayedDuration)

            addZoomButton

            if project.isTrimmed {
                trimBadge
            }

            Spacer()

            HStack(spacing: 10) {
                TimelineShortcutHint(key: "I", description: "Mark in")
                TimelineShortcutHint(key: "O", description: "Mark out")
                TimelineShortcutHint(key: "⌫", description: "Reset trim")
            }
            .help("Keyboard shortcuts")

            TimelineVolumeControl(
                systemImage: project.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill",
                value: $project.sourceAudioVolume,
                isEnabled: project.videoURL != nil,
                help: "Source audio volume"
            )

            TimelineVolumeControl(
                systemImage: "waveform",
                value: $project.narrationAudioVolume,
                isEnabled: project.narrationAudioURL != nil,
                help: "Voiceover volume"
            )
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var displayedDuration: Double {
        project.timelineDuration
    }

    /// Adds a zoom segment at the current playhead. If the playhead is already inside an
    /// existing segment, selects it instead of stacking a new one on top.
    private var addZoomButton: some View {
        Button(action: addZoomAtPlayhead) {
            HStack(spacing: 4) {
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text("Add zoom")
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color(hex: "#6466FA") ?? .accentColor)
            )
        }
        .buttonStyle(.plain)
        .disabled(project.videoURL == nil)
        .opacity(project.videoURL == nil ? 0.4 : 1.0)
        .help("Add a zoom at the playhead")
    }

    private func addZoomAtPlayhead() {
        guard project.videoURL != nil else { return }
        let t = project.currentSeconds
        if let existing = project.segment(containing: t) {
            project.selectedAnimationID = existing.id
            return
        }
        _ = project.addZoomSegment(at: t)
    }

    private var trimBadge: some View {
        HStack(spacing: 4) {
            Image(systemName: "scissors")
            Text(String(format: "%.2fs trimmed", max(0, project.durationSeconds - project.clipDuration)))
            Button {
                project.trimStartTime = 0
                project.trimEndTime = project.durationSeconds
                project.clipTimelineStart = 0
            } label: {
                Image(systemName: "xmark.circle.fill")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.7))
            .help("Reset trim")
        }
        .font(.system(size: 10, weight: .semibold, design: .rounded))
        .foregroundStyle(.black.opacity(0.85))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule().fill(Color(red: 1.0, green: 0.82, blue: 0.10))
        )
    }
}

private struct TimelineVolumeControl: View {
    let systemImage: String
    @Binding var value: Double
    let isEnabled: Bool
    let help: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(isEnabled ? 0.82 : 0.35))
                .frame(width: 18, height: 18)

            Slider(value: $value, in: 0...1)
                .controlSize(.mini)
                .frame(width: 72)
        }
        .frame(width: 96, alignment: .leading)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1.0 : 0.45)
        .help(help)
    }
}
