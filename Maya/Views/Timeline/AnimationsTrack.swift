import SwiftUI

struct AnimationsTrack: View {
    @Bindable var project: Project
    let height: CGFloat
    let onSelectSegment: (ZoomSegment) -> Void

    @State private var hoverX: CGFloat?
    @State private var activeSegmentDragID: ZoomSegment.ID?
    /// Set by a SegmentBlock during drag when its snapped time matches the playhead.
    /// We render a vertical guide line at that x coordinate as long as it is set.
    @State private var snapGuideX: CGFloat?

    static let snapStep: Double = 0.25
    static let playheadSnapTolerance: Double = 0.15
    static let dragCoordinateSpace = "Maya.AnimationsTrack.drag"

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let duration = project.timelineDuration
            // Offset converting a segment's source-time startTime into a timeline-time x.
            let clipDisplayOffset = project.clipTimelineStart - project.trimStartTime

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )

                // Existing segments. Segments live in source coords; we shift them by
                // `clipDisplayOffset` so they appear under the clip's current timeline window.
                ForEach(project.animations) { segment in
                    let isLive = segment.endTime > project.trimStartTime && segment.startTime < project.trimEndTime
                    SegmentBlock(
                        segment: segment,
                        isSelected: project.selectedAnimationID == segment.id,
                        isLive: isLive,
                        trackWidth: width,
                        totalDuration: duration,
                        clipDisplayOffset: clipDisplayOffset,
                        sourceRange: project.trimStartTime...project.trimEndTime,
                        blockedSegments: project.animations.filter { $0.id != segment.id },
                        playheadTime: project.currentSeconds,
                        height: height - 12,
                        resolveChange: { candidate in
                            project.nonOverlappingZoomSegment(candidate, excluding: segment.id)
                        },
                        onTap: {
                            project.selectedAnimationID = segment.id
                            onSelectSegment(segment)
                        },
                        onChange: { updated in
                            project.updateZoomSegment(updated)
                        },
                        onDelete: { project.removeZoomSegment(id: segment.id) },
                        onSnap: { snappedTime in
                            if let t = snappedTime, duration > 0 {
                                snapGuideX = CGFloat(t / duration) * width
                            } else {
                                snapGuideX = nil
                            }
                        },
                        onDragActivityChanged: { isDragging in
                            activeSegmentDragID = isDragging ? segment.id : nil
                        }
                    )
                }

                // Snap guide: vertical accent line drawn at the snapped time during a drag.
                if let gx = snapGuideX {
                    Rectangle()
                        .fill(Color(red: 1.0, green: 0.82, blue: 0.10))
                        .frame(width: 1, height: height - 8)
                        .offset(x: gx - 0.5, y: 4)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }

                // Hover-to-add: only when a full default zoom can fit at this spot.
                if let hx = hoverX, activeSegmentDragID == nil, duration > 0 {
                    let time = (Double(hx) / Double(width)) * duration
                    let snapped = Self.snap(time, toPlayhead: project.currentSeconds)
                    if project.canAddZoomSegment(at: snapped) {
                        HoverAddButton(hx: hx, height: height) {
                            if let segment = project.addZoomSegment(at: snapped) {
                                onSelectSegment(segment)
                            }
                        }
                    }
                }
            }
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .coordinateSpace(name: Self.dragCoordinateSpace)
            .onContinuousHover { phase in
                guard activeSegmentDragID == nil else {
                    hoverX = nil
                    return
                }
                switch phase {
                case .active(let p):
                    hoverX = max(0, min(p.x, width))
                case .ended:
                    hoverX = nil
                }
            }
        }
        .frame(height: height)
    }

    static func snap(_ t: Double, toPlayhead playheadTime: Double? = nil) -> Double {
        if let p = playheadTime, abs(t - p) < playheadSnapTolerance {
            return p
        }
        return (t / snapStep).rounded() * snapStep
    }

    static func snapToPlayhead(_ t: Double, playheadTime: Double) -> Double {
        abs(t - playheadTime) < playheadSnapTolerance ? playheadTime : t
    }
}

// MARK: - Time tooltip

struct TimeTooltip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.black.opacity(0.88))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.white.opacity(0.15), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.4), radius: 4, y: 2)
            .fixedSize()
            .transition(.opacity)
    }
}

func formatTimestamp(_ t: Double) -> String {
    let safe = max(t, 0)
    let total = Int(safe)
    let m = total / 60
    let s = total % 60
    let cs = Int((safe - floor(safe)) * 100)
    return String(format: "%d:%02d.%02d", m, s, cs)
}

// MARK: - Segment block (movable + resizable)

private struct SegmentBlock: View {
    let segment: ZoomSegment
    let isSelected: Bool
    let isLive: Bool
    let trackWidth: CGFloat
    /// Timeline duration the track is mapped to (`project.timelineDuration`).
    let totalDuration: Double
    /// Constant offset to add to a source-time value to get a timeline-time value:
    /// `clipTimelineStart - trimStartTime`. Lets the block render at the right spot
    /// even as the clip is moved around on the timeline.
    let clipDisplayOffset: Double
    let sourceRange: ClosedRange<Double>
    let blockedSegments: [ZoomSegment]
    /// Playhead position in *timeline* coords (matches the on-screen ruler).
    let playheadTime: Double
    let height: CGFloat
    let resolveChange: (ZoomSegment) -> ZoomSegment?
    let onTap: () -> Void
    let onChange: (ZoomSegment) -> Void
    let onDelete: () -> Void
    /// Snap callback receives the *timeline* time it snapped to (or nil).
    let onSnap: (Double?) -> Void
    let onDragActivityChanged: (Bool) -> Void

    @State private var dragSnapshot: (start: Double, duration: Double)?
    @State private var previewSegment: ZoomSegment?
    @State private var tooltipText: String?
    @State private var isHovering: Bool = false
    @State private var snappedPreviewTime: Double?

    private var renderedSegment: ZoomSegment { previewSegment ?? segment }

    /// Timeline position to render this segment's left edge at.
    private var displayStartTime: Double { renderedSegment.startTime + clipDisplayOffset }
    private var displayEndTime: Double { renderedSegment.endTime + clipDisplayOffset }

    private var startX: CGFloat {
        guard totalDuration > 0 else { return 0 }
        return CGFloat(displayStartTime / totalDuration) * trackWidth
    }

    private var blockWidth: CGFloat {
        guard totalDuration > 0 else { return 60 }
        return max(CGFloat(renderedSegment.duration / totalDuration) * trackWidth, 36)
    }

    var body: some View {
        ZStack {
            content
            // Left handle
            handle(
                alignment: .leading,
                onDrag: { translation in
                    resize(.leading, translation: translation, snapToGrid: false)
                },
                onEnd: { translation in
                    resize(.leading, translation: translation, snapToGrid: true)
                }
            )
            // Right handle
            handle(
                alignment: .trailing,
                onDrag: { translation in
                    resize(.trailing, translation: translation, snapToGrid: false)
                },
                onEnd: { translation in
                    resize(.trailing, translation: translation, snapToGrid: true)
                }
            )
        }
        .frame(width: blockWidth, height: height)
        .overlay(alignment: .top) {
            if let text = tooltipText {
                TimeTooltip(text: text)
                    .offset(y: -28)
                    .zIndex(10)
            }
        }
        .offset(x: startX, y: 6)
        .zIndex(dragSnapshot == nil ? 0 : 20)
        .brightness(isHovering ? 0.06 : 0)
        .animation(.easeOut(duration: 0.15), value: isHovering)
        .onHover { isHovering = $0 }
        .contextMenu {
            Button("Edit zoom") { onTap() }
            Button(role: .destructive) { onDelete() } label: { Label("Delete zoom", systemImage: "trash") }
        }
    }

    private var content: some View {
        VStack(spacing: 2) {
            Image(systemName: segment.focus.systemImage)
                .font(.system(size: 13, weight: .semibold))
            HStack(spacing: 4) {
                Text(String(format: "%.1f×", renderedSegment.scale))
                Text("·")
                Text(String(format: "%.1fs", renderedSegment.duration))
            }
            .font(.system(size: 9, weight: .medium, design: .rounded))
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            LinearGradient(
                colors: [Color(hex: "#818CF8") ?? .indigo, Color(hex: "#6466FA") ?? .indigo],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.white : Color.white.opacity(0.15),
                        lineWidth: isSelected ? 2 : 1)
        )
        .shadow(color: .black.opacity(0.3), radius: 6, y: 2)
        // When the panel is editing this segment, glow ring around the block makes the
        // connection between block and panel unambiguous.
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(hex: "#6466FA") ?? .accentColor, lineWidth: 2)
                .blur(radius: 6)
                .opacity(isSelected ? 0.85 : 0)
                .padding(-3)
                .allowsHitTesting(false)
        )
        .opacity(isLive ? 1.0 : 0.4)
        .saturation(isLive ? 1.0 : 0.5)
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .gesture(
            DragGesture(minimumDistance: 3, coordinateSpace: .named(AnimationsTrack.dragCoordinateSpace))
                .onChanged { v in
                    beginDragIfNeeded()
                    let dt = (Double(v.translation.width) / Double(trackWidth)) * totalDuration
                    let raw = (dragSnapshot?.start ?? 0) + dt
                    let playheadSource = playheadTime - clipDisplayOffset
                    let liveStart = AnimationsTrack.snapToPlayhead(raw, playheadTime: playheadSource)
                    var s = dragBaseSegment
                    s.startTime = clampedMovementStart(liveStart, duration: s.duration)
                    applyPreview(s, showsTooltip: false)
                }
                .onEnded { v in
                    if let snap = dragSnapshot {
                        let dt = (Double(v.translation.width) / Double(trackWidth)) * totalDuration
                        let raw = snap.start + dt
                        let playheadSource = playheadTime - clipDisplayOffset
                        let snapped = AnimationsTrack.snap(raw, toPlayhead: playheadSource)
                        var s = dragBaseSegment
                        s.startTime = clampedMovementStart(snapped, duration: s.duration)
                        commitChange(s)
                    }
                    endDrag()
                }
        )
    }

    private func handle(
        alignment: HorizontalAlignment,
        onDrag: @escaping (CGFloat) -> Void,
        onEnd: @escaping (CGFloat) -> Void
    ) -> some View {
        let isLeading = alignment == .leading
        return Capsule()
            .fill(Color.white.opacity(isSelected ? 0.7 : 0.32))
            .frame(width: 3, height: height * 0.55)
            .padding(.horizontal, 6)
            .background(Color.white.opacity(0.001))
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, alignment: isLeading ? .leading : .trailing)
            .onHover { hovering in
                if hovering { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
            }
            .gesture(
                DragGesture(minimumDistance: 2, coordinateSpace: .named(AnimationsTrack.dragCoordinateSpace))
                    .onChanged { v in
                        beginDragIfNeeded()
                        onDrag(v.translation.width)
                    }
                    .onEnded { v in
                        onEnd(v.translation.width)
                        endDrag()
                    }
            )
    }

    private enum Edge { case leading, trailing }

    private var dragBaseSegment: ZoomSegment {
        var s = segment
        if let snap = dragSnapshot {
            s.startTime = snap.start
            s.duration = snap.duration
        }
        return s
    }

    private func beginDragIfNeeded() {
        guard dragSnapshot == nil else { return }
        dragSnapshot = (renderedSegment.startTime, renderedSegment.duration)
        previewSegment = renderedSegment
        onDragActivityChanged(true)
    }

    private func endDrag() {
        dragSnapshot = nil
        previewSegment = nil
        tooltipText = nil
        updateSnapGuide(nil)
        onDragActivityChanged(false)
    }

    private func clampedStart(_ start: Double, duration: Double) -> Double {
        max(sourceRange.lowerBound, min(start, max(sourceRange.upperBound - duration, sourceRange.lowerBound)))
    }

    private func clampedMovementStart(_ start: Double, duration: Double) -> Double {
        guard let snap = dragSnapshot else { return clampedStart(start, duration: duration) }
        let previousEnd = blockedSegments
            .filter { $0.endTime <= snap.start }
            .map(\.endTime)
            .max() ?? sourceRange.lowerBound
        let nextStart = blockedSegments
            .filter { $0.startTime >= snap.start + snap.duration }
            .map(\.startTime)
            .min() ?? sourceRange.upperBound
        return max(previousEnd, min(start, max(nextStart - duration, previousEnd)))
    }

    private func applyPreview(_ segment: ZoomSegment, showsTooltip: Bool = true) {
        var resolved = segment
        resolved.normalize()
        previewSegment = resolved
        let displayStart = resolved.startTime + clipDisplayOffset
        let displayEnd = resolved.endTime + clipDisplayOffset
        tooltipText = showsTooltip ? "\(formatTimestamp(displayStart)) → \(formatTimestamp(displayEnd))" : nil
        updateSnapGuide(abs(displayStart - playheadTime) < 0.001 ? playheadTime : nil)
    }

    private func commitChange(_ segment: ZoomSegment) {
        guard let resolved = resolveChange(segment) else { return }
        onChange(resolved)
    }

    private func updateSnapGuide(_ time: Double?) {
        guard snappedPreviewTime != time else { return }
        snappedPreviewTime = time
        onSnap(time)
    }

    private func resize(_ edge: Edge, translation: CGFloat, snapToGrid: Bool) {
        guard let snap = dragSnapshot else { return }
        let dt = (Double(translation) / Double(trackWidth)) * totalDuration
        let playheadSource = playheadTime - clipDisplayOffset
        var s = dragBaseSegment
        switch edge {
        case .leading:
            let endTime = snap.start + snap.duration
            let previousEnd = blockedSegments
                .filter { $0.endTime <= endTime }
                .map(\.endTime)
                .max() ?? sourceRange.lowerBound
            let earliestStart = max(previousEnd, endTime - ZoomSegment.durationRange.upperBound)
            let latestStart = endTime - ZoomSegment.durationRange.lowerBound
            let proposedStart = max(earliestStart, min(snap.start + dt, latestStart))
            let nextStart = snapToGrid
                ? AnimationsTrack.snap(proposedStart, toPlayhead: playheadSource)
                : AnimationsTrack.snapToPlayhead(proposedStart, playheadTime: playheadSource)
            s.startTime = max(earliestStart, min(nextStart, latestStart))
            s.duration = endTime - s.startTime
        case .trailing:
            let nextSegmentStart = blockedSegments
                .filter { $0.startTime >= snap.start }
                .map(\.startTime)
                .min() ?? sourceRange.upperBound
            let maxDur = min(
                sourceRange.upperBound - s.startTime,
                nextSegmentStart - s.startTime,
                ZoomSegment.durationRange.upperBound
            )
            let proposedDuration = max(ZoomSegment.durationRange.lowerBound,
                                       min(snap.duration + dt, maxDur))
            let proposedEnd = s.startTime + proposedDuration
            let endTime = snapToGrid
                ? AnimationsTrack.snap(proposedEnd, toPlayhead: playheadSource)
                : AnimationsTrack.snapToPlayhead(proposedEnd, playheadTime: playheadSource)
            let clampedEnd = max(
                s.startTime + ZoomSegment.durationRange.lowerBound,
                min(endTime, s.startTime + maxDur)
            )
            s.duration = clampedEnd - s.startTime
        }
        if snapToGrid {
            commitChange(s)
        } else {
            applyPreview(s)
        }
    }
}

// MARK: - Hover add affordance

private struct HoverAddButton: View {
    let hx: CGFloat
    let height: CGFloat
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "plus.circle.fill")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.white, Color(hex: "#6466FA") ?? .indigo)
                .background(Circle().fill(.black.opacity(0.4)))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .position(x: hx, y: height / 2)
        .help("Add zoom event here")
        .transition(.opacity)
    }
}
