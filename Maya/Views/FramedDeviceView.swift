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

    private var phoneSize: CGSize {
        let h = canvasSize.height * Self.naturalHeightFraction
        let w = h * project.deviceFrame.frameAspectRatio
        return CGSize(width: w, height: h)
    }

    private var screenRect: CGRect {
        project.deviceFrame.screenRect(in: phoneSize)
    }

    private var screenCornerFraction: CGFloat {
        let radius = project.deviceFrame.screenCornerRadiusNormalized * phoneSize.width
        return screenRect.width > 0 ? radius / screenRect.width : 0
    }

    private var sampled: AnimationSample {
        AnimationSampler.sample(
            at: project.currentSeconds,
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

            DeviceFrameOverlay(frame: project.deviceFrame)
                .frame(width: phoneSize.width, height: phoneSize.height)
        }
        .frame(width: phoneSize.width, height: phoneSize.height)
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
            let islandWidth = size.width * 0.30
            let islandHeight = size.width * 0.075
            let islandY = screenRect.minY + size.width * 0.045

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

                Capsule()
                    .fill(.black)
                    .frame(width: islandWidth, height: islandHeight)
                    .position(x: size.width / 2, y: islandY + islandHeight / 2)
            }
            .compositingGroup()
            .shadow(color: .black.opacity(0.35), radius: size.width * 0.04, x: 0, y: size.width * 0.02)
        }
    }
}
