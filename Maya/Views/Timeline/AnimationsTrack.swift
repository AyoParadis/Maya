import SwiftUI

struct AnimationsTrack: View {
    @Bindable var project: Project
    let height: CGFloat
    let onSelectSegment: (ZoomSegment) -> Void

    @State private var hoverX: CGFloat?

    static let snapStep: Double = 0.25
    static let playheadSnapTolerance: Double = 0.15

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let duration = project.durationSeconds

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.white.opacity(0.06), lineWidth: 1)
                    )

                // Existing segments
                ForEach(project.animations) { segment in
                    SegmentBlock(
                        segment: segment,
                        isSelected: project.selectedAnimationID == segment.id,
                        trackWidth: width,
                        totalDuration: duration,
                        playheadTime: project.currentSeconds,
                        height: height - 12,
                        onTap: {
                            project.selectedAnimationID = segment.id
                            onSelectSegment(segment)
                        },
                        onChange: { updated in
                            project.updateZoomSegment(updated)
                        },
                        onDelete: { project.removeZoomSegment(id: segment.id) }
                    )
                }

                // Hover-to-add: only when not over an existing segment.
                if let hx = hoverX, duration > 0 {
                    let time = (Double(hx) / Double(width)) * duration
                    if project.segment(containing: time) == nil {
                        HoverAddButton(hx: hx, height: height) {
                            let snapped = Self.snap(time, toPlayhead: project.currentSeconds)
                            let segment = project.addZoomSegment(at: snapped)
                            onSelectSegment(segment)
                        }
                    }
                }
            }
            .frame(width: width, height: height)
            .contentShape(Rectangle())
            .onContinuousHover { phase in
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
    let trackWidth: CGFloat
    let totalDuration: Double
    let playheadTime: Double
    let height: CGFloat
    let onTap: () -> Void
    let onChange: (ZoomSegment) -> Void
    let onDelete: () -> Void

    @State private var dragSnapshot: (start: Double, duration: Double)?
    @State private var tooltipText: String?

    private var startX: CGFloat {
        guard totalDuration > 0 else { return 0 }
        return CGFloat(segment.startTime / totalDuration) * trackWidth
    }

    private var blockWidth: CGFloat {
        guard totalDuration > 0 else { return 60 }
        return max(CGFloat(segment.duration / totalDuration) * trackWidth, 36)
    }

    var body: some View {
        ZStack {
            content
            // Left handle
            handle(alignment: .leading) { translation in
                resize(.leading, translation: translation)
            }
            // Right handle
            handle(alignment: .trailing) { translation in
                resize(.trailing, translation: translation)
            }
        }
        .frame(width: blockWidth, height: height)
        .overlay(alignment: .top) {
            if let text = tooltipText {
                TimeTooltip(text: text)
                    .offset(y: -28)
                    .zIndex(10)
            }
        }
        .position(x: startX + blockWidth / 2, y: (height + 12) / 2)
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
                Text(String(format: "%.1f×", segment.scale))
                Text("·")
                Text(String(format: "%.1fs", segment.duration))
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
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
        .gesture(
            DragGesture(minimumDistance: 3)
                .onChanged { v in
                    if dragSnapshot == nil { dragSnapshot = (segment.startTime, segment.duration) }
                    let dt = (Double(v.translation.width) / Double(trackWidth)) * totalDuration
                    let raw = (dragSnapshot?.start ?? 0) + dt
                    var s = segment
                    s.startTime = max(0, min(raw, max(totalDuration - s.duration, 0)))
                    onChange(s)
                    tooltipText = "\(formatTimestamp(s.startTime)) → \(formatTimestamp(s.endTime))"
                }
                .onEnded { v in
                    if let snap = dragSnapshot {
                        let dt = (Double(v.translation.width) / Double(trackWidth)) * totalDuration
                        let raw = snap.start + dt
                        let snapped = AnimationsTrack.snap(raw, toPlayhead: playheadTime)
                        var s = segment
                        s.startTime = max(0, min(snapped, max(totalDuration - s.duration, 0)))
                        onChange(s)
                    }
                    dragSnapshot = nil
                    tooltipText = nil
                }
        )
    }

    private func handle(alignment: HorizontalAlignment, onDrag: @escaping (CGFloat) -> Void) -> some View {
        let isLeading = alignment == .leading
        return Capsule()
            .fill(Color.white.opacity(isSelected ? 0.55 : 0.28))
            .frame(width: 3, height: height * 0.55)
            .padding(.horizontal, 6)
            .background(Color.white.opacity(0.001))
            .contentShape(Rectangle())
            .frame(maxWidth: .infinity, alignment: isLeading ? .leading : .trailing)
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { v in
                        if dragSnapshot == nil { dragSnapshot = (segment.startTime, segment.duration) }
                        onDrag(v.translation.width)
                    }
                    .onEnded { _ in
                        dragSnapshot = nil
                        tooltipText = nil
                    }
            )
    }

    private enum Edge { case leading, trailing }

    private func resize(_ edge: Edge, translation: CGFloat) {
        guard let snap = dragSnapshot else { return }
        let dt = (Double(translation) / Double(trackWidth)) * totalDuration
        var s = segment
        switch edge {
        case .leading:
            let snappedStart = max(0, snap.start + dt)
            let endTime = snap.start + snap.duration
            let newDuration = max(ZoomSegment.durationRange.lowerBound, endTime - snappedStart)
            s.startTime = snappedStart
            s.duration = min(newDuration, ZoomSegment.durationRange.upperBound)
            tooltipText = formatTimestamp(s.startTime)
        case .trailing:
            let maxDur = min(totalDuration - s.startTime, ZoomSegment.durationRange.upperBound)
            let proposedDuration = max(ZoomSegment.durationRange.lowerBound,
                                       min(snap.duration + dt, maxDur))
            let endTime = s.startTime + proposedDuration
            s.duration = max(ZoomSegment.durationRange.lowerBound, endTime - s.startTime)
            tooltipText = "\(formatTimestamp(s.endTime)) · \(String(format: "%.2fs", s.duration))"
        }
        onChange(s)
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
