import SwiftUI

struct NarratedImagesCanvasView: View {
    @Bindable var project: NarratedImageProject
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
                    NarratedImageScenePreview(scene: sample.scene, project: project, previewTime: sample.localTime)
                } else {
                    EmptyCanvasPrompt(
                        icon: "photo.badge.plus",
                        title: "Drop images here",
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

private struct NarratedImageScenePreview: View {
    @Bindable var scene: NarratedImageScene
    @Bindable var project: NarratedImageProject
    let previewTime: Double
    @State private var captionWidthDragStart: Double?

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                if let imageURL = scene.imageURL {
                    CachedImageView(url: imageURL, maxPixelSize: 1920) {
                        Color.black
                    }
                    .scaledToFill()
                    .scaleEffect(scale)
                    .offset(x: offset.width, y: offset.height)
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                } else {
                    Color.black
                }

                LinearGradient(
                    colors: [.black.opacity(0), .black.opacity(0.4)],
                    startPoint: .center,
                    endPoint: .bottom
                )

                captionSafeZoneOverlay(size: proxy.size)

                if let beat = project.activeCaption(for: scene, at: previewTime) {
                    Text(beat.text.uppercased())
                        .font(captionFont(for: beat, width: proxy.size.width))
                        .multilineTextAlignment(.center)
                        .lineLimit(3)
                        .minimumScaleFactor(0.55)
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.95), radius: 0, x: 2, y: 2)
                        .shadow(color: .black.opacity(0.75), radius: 8, y: 5)
                        .padding(.horizontal, max(14, proxy.size.width * 0.035))
                        .frame(width: proxy.size.width * max(0.38, min(0.96, scene.captionBoxWidth)))
                        .contentShape(Rectangle())
                        .overlay(alignment: .trailing) {
                            Capsule()
                                .fill(Color.white.opacity(0.82))
                                .frame(width: 5, height: max(30, proxy.size.height * 0.08))
                                .shadow(color: .black.opacity(0.35), radius: 4, y: 2)
                                .gesture(
                                    DragGesture(minimumDistance: 0)
                                        .onChanged { value in
                                            if captionWidthDragStart == nil {
                                                captionWidthDragStart = scene.captionBoxWidth
                                            }
                                            let start = captionWidthDragStart ?? scene.captionBoxWidth
                                            scene.captionBoxWidth = max(0.38, min(0.96, start + Double(value.translation.width / max(proxy.size.width, 1))))
                                        }
                                        .onEnded { _ in captionWidthDragStart = nil }
                                )
                                .help("Drag to stretch caption width")
                        }
                        .position(captionPosition(size: proxy.size))
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    scene.captionAnchor = CGPoint(
                                        x: max(0.08, min(0.92, value.location.x / max(proxy.size.width, 1))),
                                        y: max(0.08, min(0.92, value.location.y / max(proxy.size.height, 1)))
                                    )
                                }
                        )
                        .help("Drag to place this scene's captions")
                } else if !scene.script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("Generate captions")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.82))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.38), in: RoundedRectangle(cornerRadius: 8))
                        .position(captionPosition(size: proxy.size))
                }
            }
        }
    }

    private var scale: CGFloat {
        let p = min(1, max(0, previewTime / max(0.5, scene.duration)))
        let eased = 0.5 - cos(p * .pi) * 0.5
        switch scene.motionPreset {
        case .still: return 1
        case .subtleZoom, .auto: return 1 + eased * 0.06
        case .punchZoom: return 1 + eased * 0.12
        case .pan: return 1.06
        }
    }

    private var offset: CGSize {
        let p = min(1, max(0, previewTime / max(0.5, scene.duration)))
        if scene.motionPreset == .pan {
            return CGSize(width: (p - 0.5) * 28, height: 0)
        }
        return .zero
    }

    private func captionPosition(size: CGSize) -> CGPoint {
        CGPoint(
            x: size.width * max(0.08, min(0.92, scene.captionAnchor.x)),
            y: size.height * max(0.08, min(0.92, scene.captionAnchor.y))
        )
    }

    private func captionSafeZoneOverlay(size: CGSize) -> some View {
        let rect = CGRect(
            x: size.width * 0.08,
            y: size.height * 0.18,
            width: size.width * 0.76,
            height: size.height * 0.62
        )
        return RoundedRectangle(cornerRadius: 10)
            .stroke(style: StrokeStyle(lineWidth: 1, dash: [5, 6]))
            .foregroundStyle(Color.white.opacity(0.16))
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
    }

    private func fontSize(for beat: NarratedCaptionBeat, width: CGFloat) -> CGFloat {
        let base = width * (beat.style == .softSubtitle ? 0.07 : 0.105) * max(0.72, min(1.45, scene.captionFontScale))
        if beat.text.count <= 8 { return min(width * 0.15, base * 1.16) }
        if beat.text.count >= 24 { return max(30, base * 0.72) }
        return max(32, base)
    }

    private func captionFont(for beat: NarratedCaptionBeat, width: CGFloat) -> Font {
        let size = fontSize(for: beat, width: width)
        guard let family = scene.captionFontFamily, !family.isEmpty else {
            return .system(size: size, weight: .black)
        }
        return .custom(family, size: size).weight(.black)
    }
}
