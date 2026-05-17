import AppKit
import SwiftUI

struct CanvasView: View {
    @Bindable var project: Project
    let blurPoster: NSImage?

    var body: some View {
        GeometryReader { proxy in
            let aspect = project.canvasAspect.ratio
            let availW = proxy.size.width
            let availH = proxy.size.height
            let canvasSize: CGSize = {
                if availW / max(availH, 1) > aspect {
                    let h = availH
                    return CGSize(width: h * aspect, height: h)
                } else {
                    let w = availW
                    return CGSize(width: w, height: w / aspect)
                }
            }()

            ZStack {
                BackgroundView(background: project.background, blurPoster: blurPoster)
                    .frame(width: canvasSize.width, height: canvasSize.height)
                    .clipped()

                if project.videoURL != nil {
                    FramedDeviceView(project: project, canvasSize: canvasSize)
                    PlaybackOverlay(project: project)
                        .padding(14)
                        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .bottom)
                } else {
                    DropPromptView()
                        .frame(width: canvasSize.width, height: canvasSize.height)
                }
            }
            .frame(width: canvasSize.width, height: canvasSize.height)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.black.opacity(0.1), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.25), radius: 18, x: 0, y: 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .padding(24)
    }
}

private struct PlaybackOverlay: View {
    @Bindable var project: Project

    var body: some View {
        HStack(spacing: 10) {
            Button {
                project.togglePlayback()
            } label: {
                Image(systemName: project.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 16, weight: .bold))
                    .frame(width: 34, height: 34)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(Circle().fill(Color.black.opacity(0.5)))
            .help("Play / Pause (Space)")

            Text("\(formatPlaybackTimestamp(project.currentSeconds)) / \(formatPlaybackTimestamp(project.durationSeconds))")
                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(.white.opacity(0.92))
                .lineLimit(1)
                .frame(minWidth: 88, alignment: .leading)

            Slider(
                value: Binding(
                    get: { project.currentSeconds },
                    set: { project.seek(to: $0) }
                ),
                in: 0...max(project.durationSeconds, 0.1)
            )
            .controlSize(.small)
            .frame(minWidth: 120)
            .help("Scrub the recording")

            Button {
                project.toggleMute()
            } label: {
                Image(systemName: project.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 30, height: 30)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .help("Mute (M)")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.black.opacity(0.46), in: Capsule())
        .overlay(Capsule().stroke(.white.opacity(0.16), lineWidth: 1))
        .shadow(color: .black.opacity(0.28), radius: 12, y: 5)
        .padding(.horizontal, 12)
    }
}

private func formatPlaybackTimestamp(_ seconds: Double) -> String {
    guard seconds.isFinite, seconds >= 0 else { return "0:00" }
    let total = Int(seconds.rounded(.down))
    return String(format: "%d:%02d", total / 60, total % 60)
}

private struct DropPromptView: View {
    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "iphone.gen3")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.white.opacity(0.85))
            Text("Drop an iPhone screen recording here")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.85))
            Text("or use Open… in the sidebar")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.6))
        }
        .padding()
        .background(Color.black.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
