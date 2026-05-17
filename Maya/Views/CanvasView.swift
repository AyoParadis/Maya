import AppKit
import SwiftUI

struct CanvasView: View {
    @Bindable var project: Project
    let blurPoster: NSImage?
    let onOpenRecording: () -> Void

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
                } else {
                    DropPromptView(onOpenRecording: onOpenRecording)
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

private struct DropPromptView: View {
    let onOpenRecording: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: "iphone.gen3")
                .font(.system(size: 56, weight: .light))
                .foregroundStyle(.white.opacity(0.85))
            Text("Drop an iPhone screen recording here")
                .font(.title3)
                .foregroundStyle(.white.opacity(0.85))
            Button {
                onOpenRecording()
            } label: {
                Label("Open from Finder", systemImage: "folder")
                    .font(.callout.weight(.semibold))
                    .frame(minWidth: 170)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)

            Text("or drag a video onto the canvas")
                .font(.callout)
                .foregroundStyle(.white.opacity(0.62))
        }
        .padding(22)
        .background(Color.black.opacity(0.25))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
