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
        case .physical, .drawn:
            return project.deviceFrame.frameAspectRatio
        }
    }

    private var phoneSize: CGSize {
        DeviceFrame.fittedSize(
            aspectRatio: effectiveAspectRatio,
            in: canvasSize,
            maxHeightFraction: Self.naturalHeightFraction,
            maxWidthFraction: Self.naturalHeightFraction
        )
    }

    private var screenRect: CGRect {
        project.deviceFrame.screenRect(in: phoneSize)
    }

    /// Absolute corner radius (in pt) used to mask the video.
    private var screenCornerRadius: CGFloat {
        switch project.deviceFrame.kind {
        case .physical, .drawn:
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

            switch project.deviceFrame.kind {
            case .physical, .drawn:
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
    private var metal: Color { Color(hex: frame.swatchHex) ?? Color(white: 0.12) }

    var body: some View {
        GeometryReader { g in
            let size = g.size
            let bezelRadius = size.width * frame.outerCornerRadiusFraction
            let screenRect = frame.screenRect(in: size)
            let screenRadius = frame.screenCornerRadius(in: size)

            ZStack {
                frameHull(size: size, bezelRadius: bezelRadius, screenRect: screenRect)

                RoundedRectangle(cornerRadius: screenRadius)
                    .frame(width: screenRect.width, height: screenRect.height)
                    .position(x: screenRect.midX, y: screenRect.midY)
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
            .shadow(color: .black.opacity(0.35), radius: size.width * 0.04, x: 0, y: size.width * 0.02)
        }
    }

    @ViewBuilder
    private func frameHull(size: CGSize, bezelRadius: CGFloat, screenRect: CGRect) -> some View {
        switch frame.style {
        case .laptop:
            laptopHull(size: size, screenRect: screenRect)
        case .tablet:
            tabletHull(size: size, bezelRadius: bezelRadius)
        case .androidPhone:
            androidHull(size: size, bezelRadius: bezelRadius)
        case .classicPhone, .modernPhone:
            phoneHull(size: size, bezelRadius: bezelRadius)
        }
    }

    private func phoneHull(size: CGSize, bezelRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: bezelRadius)
            .fill(
                LinearGradient(
                    colors: [metal.lightened(0.18), metal, metal.darkened(0.28)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: bezelRadius)
                    .stroke(Color.white.opacity(0.22), lineWidth: max(1, size.width * 0.004))
            )
            .overlay(alignment: .top) {
                if frame.style == .classicPhone {
                    Capsule()
                        .fill(Color.black.opacity(0.28))
                        .frame(width: size.width * 0.18, height: max(2, size.width * 0.012))
                        .padding(.top, size.height * 0.018)
                }
            }
    }

    private func androidHull(size: CGSize, bezelRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: bezelRadius)
            .fill(
                LinearGradient(
                    colors: [metal.lightened(0.12), metal.darkened(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(RoundedRectangle(cornerRadius: bezelRadius).stroke(.white.opacity(0.18), lineWidth: max(1, size.width * 0.004)))
            .overlay(alignment: .top) {
                Circle()
                    .fill(.black.opacity(0.5))
                    .frame(width: size.width * 0.035, height: size.width * 0.035)
                    .padding(.top, size.height * 0.018)
            }
    }

    private func tabletHull(size: CGSize, bezelRadius: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: bezelRadius)
            .fill(
                LinearGradient(
                    colors: [metal.lightened(0.16), metal.darkened(0.18)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(RoundedRectangle(cornerRadius: bezelRadius).stroke(.white.opacity(0.2), lineWidth: max(1, size.width * 0.004)))
            .overlay(alignment: .top) {
                Circle()
                    .fill(.black.opacity(0.3))
                    .frame(width: size.width * 0.022, height: size.width * 0.022)
                    .padding(.top, size.height * 0.014)
            }
    }

    private func laptopHull(size: CGSize, screenRect: CGRect) -> some View {
        ZStack(alignment: .top) {
            RoundedRectangle(cornerRadius: size.width * 0.028)
                .fill(LinearGradient(colors: [metal.lightened(0.14), metal.darkened(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(RoundedRectangle(cornerRadius: size.width * 0.028).stroke(.white.opacity(0.22), lineWidth: max(1, size.width * 0.003)))
                .padding(.bottom, size.height * 0.11)

            RoundedRectangle(cornerRadius: size.width * 0.02)
                .fill(Color.black.opacity(0.26))
                .frame(width: screenRect.width + size.width * 0.028, height: screenRect.height + size.height * 0.032)
                .offset(y: screenRect.minY - size.height * 0.016)

            VStack(spacing: 0) {
                Spacer()
                RoundedRectangle(cornerRadius: size.width * 0.018)
                    .fill(LinearGradient(colors: [metal.lightened(0.24), metal.darkened(0.12)], startPoint: .top, endPoint: .bottom))
                    .frame(height: size.height * 0.12)
                    .overlay(alignment: .top) {
                        RoundedRectangle(cornerRadius: size.width * 0.008)
                            .fill(.black.opacity(0.12))
                            .frame(width: size.width * 0.16, height: size.height * 0.012)
                            .padding(.top, size.height * 0.022)
                    }
            }
        }
    }
}

private extension DeviceFrame {
    var swatchHex: String {
        let parts = id.split(separator: ".")
        guard parts.count == 2,
              let model = DeviceModel.model(id: String(parts[0])),
              let color = model.color(id: String(parts[1])) else {
            return "#1F2937"
        }
        return color.swatchHex
    }
}

private extension Color {
    func lightened(_ amount: Double) -> Color {
        adjusted(by: abs(amount))
    }

    func darkened(_ amount: Double) -> Color {
        adjusted(by: -abs(amount))
    }

    private func adjusted(by amount: Double) -> Color {
        guard let ns = NSColor(self).usingColorSpace(.sRGB) else { return self }
        let r = min(max(ns.redComponent + amount, 0), 1)
        let g = min(max(ns.greenComponent + amount, 0), 1)
        let b = min(max(ns.blueComponent + amount, 0), 1)
        return Color(red: r, green: g, blue: b, opacity: ns.alphaComponent)
    }
}
