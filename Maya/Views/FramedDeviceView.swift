import AppKit
import SwiftUI

struct FramedDeviceView: View {
    @Bindable var project: Project
    let canvasSize: CGSize

    @State private var dragAnchor: CGSize?

    static let naturalHeightFraction: CGFloat = AnimationSampler.baseHeightFraction

    /// Drag/offset is normalized against the short side so feel stays consistent
    /// across canvas aspects (matches the compositor's use of `min(w, h)`).
    private var offsetReference: CGFloat {
        min(canvasSize.width, canvasSize.height)
    }

    /// For `.none` and `.generic` modes we don't have a frame PNG — the "phone
    /// box" follows the source video's own aspect so playback isn't letterboxed
    /// inside a fake hull.
    private var effectiveAspectRatio: CGFloat {
        switch project.deviceFrame.kind {
        case .none, .generic:
            let s = project.videoNaturalSize
            if s.width > 0 && s.height > 0 {
                return s.width / s.height
            }
            return project.deviceFrame.frameAspectRatio
        case .physical:
            return project.deviceFrame.frameAspectRatio
        }
    }

    private var phoneSize: CGSize {
        let h = canvasSize.height * Self.naturalHeightFraction
        let w = h * effectiveAspectRatio
        return CGSize(width: w, height: h)
    }

    private var screenRect: CGRect {
        project.deviceFrame.screenRect(in: phoneSize)
    }

    /// Absolute corner radius (in pt) used to mask the video.
    private var screenCornerRadius: CGFloat {
        switch project.deviceFrame.kind {
        case .physical:
            return project.deviceFrame.screenCornerRadiusNormalized * phoneSize.width
        case .none, .generic:
            return project.bareCornerRadius * min(screenRect.width, screenRect.height)
        }
    }

    private var screenCornerFraction: CGFloat {
        screenRect.width > 0 ? screenCornerRadius / screenRect.width : 0
    }

    /// Stroke width for the generic device bezel, scaled with the phone box.
    /// 0 when the user dialed the slider all the way down.
    private var bezelWidth: CGFloat {
        max(0, phoneSize.width * project.bareBezelWidth)
    }

    private var bezelColor: Color {
        Color(hex: project.bareBezelHex) ?? .black
    }

    private var sampled: AnimationSample {
        // `currentSeconds` is in timeline coords but the sampler compares against
        // animations stored in source coords. Convert before sampling so animations
        // fire on the right source frame regardless of where the clip sits.
        AnimationSampler.sample(
            at: project.timelineToSource(project.currentSeconds),
            segments: project.animations,
            baseScale: project.scale,
            baseOffset: project.offset
        )
    }

    var body: some View {
        let s = sampled
        let ref = offsetReference
        ZStack(alignment: .topLeading) {
            VideoPlayerNSView(
                player: project.player,
                cornerRadiusFraction: screenCornerFraction
            )
            .frame(width: screenRect.width, height: screenRect.height)
            .offset(x: screenRect.minX, y: screenRect.minY)

            switch project.deviceFrame.kind {
            case .physical:
                DeviceFrameOverlay(frame: project.deviceFrame)
                    .frame(width: phoneSize.width, height: phoneSize.height)
            case .generic:
                if bezelWidth > 0 {
                    genericBezel
                }
            case .none:
                EmptyView()
            }
        }
        .frame(width: phoneSize.width, height: phoneSize.height)
        .shadow(
            color: project.shadow.enabled
                ? (Color(hex: project.shadow.colorHex) ?? .black).opacity(project.shadow.opacity)
                : .clear,
            radius: project.shadow.enabled ? project.shadow.radius : 0,
            x: project.shadow.enabled ? project.shadow.offsetX : 0,
            y: project.shadow.enabled ? project.shadow.offsetY : 0
        )
        .scaleEffect(s.scale)
        .offset(
            x: s.offsetX * ref,
            y: s.offsetY * ref
        )
        .gesture(
            DragGesture()
                .onChanged { value in
                    if dragAnchor == nil { dragAnchor = project.offset }
                    let anchor = dragAnchor ?? .zero
                    project.offset = CGSize(
                        width: anchor.width + value.translation.width / ref,
                        height: anchor.height + value.translation.height / ref
                    )
                }
                .onEnded { _ in dragAnchor = nil }
        )
    }

    /// Stroke positioned so its INNER edge meets the video bounds and the
    /// stroke grows outward from there — matches the user's "border outside,
    /// not inside" requirement.
    private var genericBezel: some View {
        let w = bezelWidth
        // Stroked radius is the inner radius + half stroke so the stroke's
        // inner edge coincides with the video's rounded corner.
        return RoundedRectangle(cornerRadius: screenCornerRadius + w / 2)
            .stroke(bezelColor, lineWidth: w)
            .frame(width: phoneSize.width + w, height: phoneSize.height + w)
            .offset(x: -w / 2, y: -w / 2)
            .shadow(color: .black.opacity(0.18), radius: w * 0.6, y: w * 0.2)
    }
}

struct DeviceFrameOverlay: View {
    let frame: DeviceFrame

    var body: some View {
        if let nsImage = NSImage(named: frame.imageName), nsImage.size.width > 1 {
            Image(nsImage: nsImage)
                .resizable()
                .interpolation(.high)
        } else {
            PlaceholderFrameView(frame: frame)
        }
    }
}

struct PlaceholderFrameView: View {
    let frame: DeviceFrame

    var body: some View {
        GeometryReader { g in
            let size = g.size
            let bezelRadius = size.width * 0.135
            let screenRect = frame.screenRect(in: size)
            let screenRadius = frame.screenCornerRadius(in: size)

            ZStack {
                RoundedRectangle(cornerRadius: bezelRadius)
                    .fill(
                        LinearGradient(
                            colors: [Color(white: 0.16), Color(white: 0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: bezelRadius)
                            .stroke(
                                LinearGradient(
                                    colors: [Color(white: 0.45), Color(white: 0.15)],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: max(1, size.width * 0.004)
                            )
                    )

                RoundedRectangle(cornerRadius: screenRadius)
                    .frame(width: screenRect.width, height: screenRect.height)
                    .position(x: screenRect.midX, y: screenRect.midY)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
            .shadow(color: .black.opacity(0.35), radius: size.width * 0.04, x: 0, y: size.width * 0.02)
        }
    }
}
