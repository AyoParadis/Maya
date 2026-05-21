import AppKit
import SwiftUI

struct CanvasView: View {
    @Bindable var project: Project
    let blurPoster: NSImage?
    let onOpenRecording: () -> Void

    var body: some View {
        StudioCanvasStage(aspect: project.canvasAspect.ratio) { canvasSize in
            ZStack {
                BackgroundView(background: project.background, blurPoster: blurPoster)
                    .frame(width: canvasSize.width, height: canvasSize.height)
                    .clipped()

                if project.videoURL != nil {
                    FramedDeviceView(project: project, canvasSize: canvasSize)
                } else {
                    EmptyCanvasPrompt(
                        icon: "iphone.gen3",
                        title: "Drop an iPhone screen recording here",
                        buttonTitle: "Open from Finder",
                        footnote: "or drag a video onto the canvas",
                        action: onOpenRecording
                    )
                        .frame(width: canvasSize.width, height: canvasSize.height)
                }
            }
        }
    }
}
