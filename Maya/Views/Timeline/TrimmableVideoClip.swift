import SwiftUI

/// Trim + position-aware video clip for the timeline.
///
/// The full timeline width represents the source video duration. The "clip" — thumbnails
/// + yellow trim chrome — is rendered ONLY in the `[trimStart, trimEnd]` window. Outside
/// that window the timeline shows empty track background (no dim, no thumbnails) so the
/// trimmed regions truly disappear.
///
/// Three interactions:
///   • Left handle  → moves trim-in (the source IN point)
///   • Right handle → moves trim-out (the source OUT point)
///   • Body drag    → slides both trim points together, keeping clip duration constant.
///                    Lets the user drop the clip wherever on the timeline, including the
///                    very start.
struct TrimmableVideoClip: View {
    @Bindable var project: Project
    let height: CGFloat
    let thumbnailCount: Int

    @State private var isHovering: Bool = false
    @State private var activeHandle: TrimEdge?
    @State private var handleDragSnapshot: (start: Double, end: Double)?
    @State private var bodyDragSnapshot: (start: Double, end: Double)?
    @State private var isDraggingBody: Bool = false

    // Single source of truth for what the cursor should look like. Each hover zone
    // updates its own bool, then `applyCursor()` reads all of them and sets the
    // correct NSCursor — avoiding the push/pop stack getting out of sync when overlap-
    // ping hover regions fire in unpredictable order.
    @State private var isHoveringBody: Bool = false
    @State private var hoveredHandle: TrimEdge?

    private enum TrimEdge { case start, end }

    private let handleWidth: CGFloat = 10
    private let handleHitWidth: CGFloat = 22
    private let trimColor = Color(red: 1.0, green: 0.82, blue: 0.10)
    private let cornerRadius: CGFloat = 8

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let duration = project.durationSeconds

            ZStack(alignment: .topLeading) {
                // Empty timeline track — shown wherever the clip isn't.
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Color.white.opacity(0.04))
                    .overlay(
                        RoundedRectangle(cornerRadius: cornerRadius)
                            .stroke(.white.opacity(0.06), lineWidth: 1)
                    )
                    .frame(width: width, height: height)

                if duration > 0, project.videoURL != nil {
                    let startX = CGFloat(project.trimStartTime / duration) * width
                    let endX = CGFloat(project.trimEndTime / duration) * width
                    let trimWidth = max(0, endX - startX)

                    clipBlock(width: width, trimWidth: trimWidth, startX: startX, duration: duration)
                        .frame(width: trimWidth, height: height)
                        .offset(x: startX)

                    handle(edge: .start, x: startX, fullWidth: width, duration: duration)
                    handle(edge: .end, x: endX, fullWidth: width, duration: duration)

                    if let edge = activeHandle {
                        let t = edge == .start ? project.trimStartTime : project.trimEndTime
                        let x = edge == .start ? startX : endX
                        TimeTooltip(text: formatTimestamp(t))
                            .offset(x: x - 28, y: -26)
                            .allowsHitTesting(false)
                    }
                }
            }
            .frame(width: width, height: height)
            .onHover { isHovering = $0 }
        }
        .frame(height: height)
    }

    /// The visible clip: full-width thumbnail strip masked to the trim window, with the
    /// yellow border and the body-drag gesture. We render the full strip and offset it so
    /// the source position aligns within the clipped frame — this keeps thumbnails at
    /// their "natural" source positions instead of regenerating thumbnails per trim.
    private func clipBlock(width: CGFloat, trimWidth: CGFloat, startX: CGFloat, duration: Double) -> some View {
        ZStack {
            if let url = project.videoURL {
                VideoThumbnailStrip(
                    url: url,
                    thumbnailCount: thumbnailCount,
                    height: height
                )
                .frame(width: width, height: height)
                .offset(x: -startX)
                .frame(width: trimWidth, height: height, alignment: .leading)
                .clipped()
            }

            RoundedRectangle(cornerRadius: cornerRadius)
                .stroke(
                    activeHandle != nil || isDraggingBody
                        ? trimColor
                        : trimColor.opacity(isHovering ? 0.9 : 0.55),
                    lineWidth: activeHandle != nil || isDraggingBody ? 3 : 2
                )
                .frame(width: trimWidth, height: height)
                .animation(.easeOut(duration: 0.15), value: activeHandle)
                .animation(.easeOut(duration: 0.15), value: isHovering)
                .animation(.easeOut(duration: 0.15), value: isDraggingBody)
        }
        .frame(width: trimWidth, height: height)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
        .contentShape(Rectangle())
        .onHover { hovering in
            isHoveringBody = hovering
            applyCursor()
        }
        .gesture(
            DragGesture(minimumDistance: 3, coordinateSpace: .local)
                .onChanged { v in
                    if bodyDragSnapshot == nil {
                        bodyDragSnapshot = (project.trimStartTime, project.trimEndTime)
                    }
                    isDraggingBody = true
                    applyCursor()
                    guard let snap = bodyDragSnapshot, width > 0, duration > 0 else { return }
                    let dur = snap.end - snap.start
                    let dt = (Double(v.translation.width) / Double(width)) * duration
                    var newStart = snap.start + dt
                    newStart = max(0, min(newStart, duration - dur))
                    project.trimStartTime = newStart
                    project.trimEndTime = newStart + dur
                    // Keep the playhead inside the moving clip so the canvas keeps making sense.
                    if project.currentSeconds < project.trimStartTime {
                        project.seek(to: project.trimStartTime)
                    } else if project.currentSeconds > project.trimEndTime {
                        project.seek(to: project.trimEndTime)
                    }
                }
                .onEnded { _ in
                    bodyDragSnapshot = nil
                    isDraggingBody = false
                    applyCursor()
                }
        )
    }

    /// Centralized cursor logic — handles always win over the body, dragging body shows
    /// closed hand, hovering body shows open hand, nothing → arrow.
    private func applyCursor() {
        if hoveredHandle != nil {
            NSCursor.resizeLeftRight.set()
        } else if isDraggingBody {
            NSCursor.closedHand.set()
        } else if isHoveringBody {
            NSCursor.openHand.set()
        } else {
            NSCursor.arrow.set()
        }
    }

    private func handle(edge: TrimEdge, x: CGFloat, fullWidth: CGFloat, duration: Double) -> some View {
        let isActive = activeHandle == edge

        return ZStack {
            Color.white.opacity(0.001)
                .frame(width: handleHitWidth, height: height)

            RoundedRectangle(cornerRadius: 3)
                .fill(trimColor)
                .frame(width: handleWidth, height: height + 8)
                .overlay(
                    RoundedRectangle(cornerRadius: 1.5)
                        .fill(Color.black.opacity(0.55))
                        .frame(width: 2, height: height * 0.4)
                )
                .shadow(color: .black.opacity(0.35), radius: isActive ? 6 : 2, y: 1)
                .scaleEffect(isActive ? 1.08 : (isHovering ? 1.02 : 1.0))
                .animation(.easeOut(duration: 0.15), value: isActive)
                .animation(.easeOut(duration: 0.15), value: isHovering)
        }
        .contentShape(Rectangle())
        .position(x: x, y: height / 2)
        .onHover { hovering in
            if hovering {
                hoveredHandle = edge
            } else if hoveredHandle == edge {
                hoveredHandle = nil
            }
            applyCursor()
        }
        .gesture(
            DragGesture(minimumDistance: 1, coordinateSpace: .local)
                .onChanged { v in
                    if handleDragSnapshot == nil {
                        handleDragSnapshot = (project.trimStartTime, project.trimEndTime)
                    }
                    activeHandle = edge
                    let dt = (Double(v.translation.width) / Double(fullWidth)) * duration
                    switch edge {
                    case .start:
                        let proposed = (handleDragSnapshot?.start ?? 0) + dt
                        project.setTrimStart(proposed)
                        if project.currentSeconds < project.trimStartTime {
                            project.seek(to: project.trimStartTime)
                        }
                    case .end:
                        let proposed = (handleDragSnapshot?.end ?? duration) + dt
                        project.setTrimEnd(proposed)
                        if project.currentSeconds > project.trimEndTime {
                            project.seek(to: project.trimEndTime)
                        }
                    }
                }
                .onEnded { _ in
                    handleDragSnapshot = nil
                    activeHandle = nil
                }
        )
    }
}
