import AppKit
import SwiftUI

struct CarouselCanvasView: View {
    @Bindable var project: CarouselProject
    let currentTime: Double
    let onImportImages: () -> Void

    var body: some View {
        StudioCanvasStage(
            aspect: project.canvasAspect.ratio,
            heightReserve: 52,
            cornerRadius: 0,
            strokeColor: Color.black.opacity(0.16),
            shadowColor: Color.black.opacity(0.22),
            shadowRadius: 20,
            shadowY: 10
        ) { canvasSize in
            let sample = project.timelineSample(at: currentTime)
            ZStack {
                BackgroundView(background: .gradient(GradientSpec.presets[0]), blurPoster: nil)
                    .frame(width: canvasSize.width, height: canvasSize.height)
                    .clipped()

                if let sample {
                    CarouselCardPreview(card: sample.card, project: project, previewTime: sample.localTime)
                    if project.showSafeZones {
                        SafeZoneOverlay(project: project)
                    }
                } else {
                    EmptyCanvasPrompt(
                        icon: "photo.on.rectangle.angled",
                        title: "Drop carousel images here",
                        buttonTitle: "Open from Finder",
                        prominentButton: false,
                        action: onImportImages
                    )
                    .foregroundStyle(.white.opacity(0.86))
                }
            }
        }
    }
}

private struct CarouselCardPreview: View {
    @Bindable var card: CarouselCard
    @Bindable var project: CarouselProject
    let previewTime: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottomLeading) {
                if let imageURL = card.imageURL, let image = NSImage(contentsOf: imageURL) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .scaleEffect(scale)
                        .offset(x: offset.width, y: offset.height)
                        .frame(width: proxy.size.width, height: proxy.size.height)
                        .clipped()
                } else {
                    ComposedSlideBackground(card: card, project: project)
                }

                LinearGradient(
                    colors: [.black.opacity(0), .black.opacity(0.46)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                VStack(alignment: .leading, spacing: 12) {
                    if !card.badge.isEmpty {
                        Text(card.badge)
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(Color(hex: project.brandHex) ?? .accentColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                    Spacer(minLength: 0)
                    if !card.headline.isEmpty {
                        Text(card.headline)
                            .font(.system(size: max(28, proxy.size.width * 0.075), weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(4)
                    }
                    if !card.subtitle.isEmpty {
                        Text(card.subtitle)
                            .font(.system(size: max(15, proxy.size.width * 0.036), weight: .medium))
                            .foregroundStyle(.white.opacity(0.88))
                            .lineLimit(4)
                    }
                    if !card.cta.isEmpty {
                        Text(card.cta)
                            .font(.system(size: max(14, proxy.size.width * 0.034), weight: .bold))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .background(Color(hex: project.brandHex) ?? .accentColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding(max(18, proxy.size.width * 0.06))
            }
        }
    }

    private var scale: CGFloat {
        let p = min(1, max(0, previewTime / max(0.5, card.duration)))
        let eased = 0.5 - cos(p * .pi) * 0.5
        switch effectiveMotion {
        case .still: return 1
        case .subtleZoom, .auto: return 1 + eased * 0.06
        case .punchZoom: return 1 + eased * 0.12
        case .pan: return 1.06
        }
    }

    private var offset: CGSize {
        let p = min(1, max(0, previewTime / max(0.5, card.duration)))
        if effectiveMotion == .pan {
            return CGSize(width: (p - 0.5) * 28, height: 0)
        }
        return .zero
    }

    private var effectiveMotion: CarouselMotionPreset {
        let motion = card.motionOverride ?? project.motionPreset
        if motion == .auto {
            return [card.headline, card.subtitle, card.cta, card.badge].joined(separator: " ").count > 130 ? .still : .subtleZoom
        }
        return motion
    }
}

private struct ComposedSlideBackground: View {
    @Bindable var card: CarouselCard
    @Bindable var project: CarouselProject

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    (Color(hex: project.brandHex) ?? .indigo).opacity(0.95),
                    Color(hex: "#377DFF")?.opacity(0.86) ?? Color.blue.opacity(0.86)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            GeometryReader { proxy in
                let spacing = max(48, proxy.size.width * 0.13)
                Path { path in
                    var x = -proxy.size.height
                    while x < proxy.size.width {
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x + proxy.size.height, y: proxy.size.height))
                        x += spacing
                    }
                }
                .stroke(.white.opacity(0.13), lineWidth: 1)
            }
            VStack {
                HStack {
                    Text(card.role.isEmpty ? "Slide" : card.role)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.58))
                    Spacer()
                }
                Spacer()
            }
            .padding(18)
        }
    }
}

private struct SafeZoneOverlay: View {
    @Bindable var project: CarouselProject

    var body: some View {
        GeometryReader { proxy in
            let inset = safeInsets(size: proxy.size)
            ZStack {
                VStack(spacing: 0) {
                    Color.black.opacity(0.18).frame(height: inset.top)
                    HStack(spacing: 0) {
                        Color.black.opacity(0.18).frame(width: inset.leading)
                        Color.clear
                        Color.black.opacity(0.18).frame(width: inset.trailing)
                    }
                    Color.black.opacity(0.18).frame(height: inset.bottom)
                }

                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [7, 6]))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(EdgeInsets(top: inset.top, leading: inset.leading, bottom: inset.bottom, trailing: inset.trailing))
            }
            .allowsHitTesting(false)
        }
    }

    private func safeInsets(size: CGSize) -> EdgeInsets {
        switch effectivePreset {
        case .reelsTikTok:
            return EdgeInsets(top: size.height * 0.10, leading: size.width * 0.07, bottom: size.height * 0.18, trailing: size.width * 0.18)
        case .feedPortrait:
            return EdgeInsets(top: size.height * 0.07, leading: size.width * 0.07, bottom: size.height * 0.09, trailing: size.width * 0.07)
        case .square:
            return EdgeInsets(top: size.height * 0.08, leading: size.width * 0.08, bottom: size.height * 0.08, trailing: size.width * 0.08)
        case .auto:
            return EdgeInsets(top: size.height * 0.08, leading: size.width * 0.08, bottom: size.height * 0.1, trailing: size.width * 0.08)
        }
    }

    private var effectivePreset: CarouselSafeZonePreset {
        if project.safeZonePreset != .auto { return project.safeZonePreset }
        switch project.canvasAspect {
        case .vertical9x16: return .reelsTikTok
        case .vertical4x5: return .feedPortrait
        case .square: return .square
        default: return .auto
        }
    }
}
