import AVFoundation
import AppKit
import SwiftUI

/// Silently loops a bundled MP4 inside SwiftUI. Used for the animation preset
/// previews — each card spins its own short clip continuously.
struct LoopingVideoView: NSViewRepresentable {
    let resourceName: String

    func makeNSView(context: Context) -> LoopingPlayerHostView {
        let view = LoopingPlayerHostView()
        view.load(resourceName: resourceName)
        return view
    }

    func updateNSView(_ nsView: LoopingPlayerHostView, context: Context) {
        if nsView.currentResource != resourceName {
            nsView.load(resourceName: resourceName)
        }
    }

    static func dismantleNSView(_ nsView: LoopingPlayerHostView, coordinator: ()) {
        nsView.stop()
    }
}

final class LoopingPlayerHostView: NSView {
    private(set) var currentResource: String?
    private var player: AVQueuePlayer?
    private var looper: AVPlayerLooper?
    private var playerLayer: AVPlayerLayer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    /// AVPlayerLayer wants a non-zero size and would otherwise claim the
    /// player's native resolution as intrinsic content size, which pushes the
    /// SwiftUI layout outward. Returning `noIntrinsicMetric` lets the parent
    /// dictate the frame.
    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
    }

    override func layout() {
        super.layout()
        playerLayer?.frame = bounds
    }

    func load(resourceName: String) {
        stop()
        currentResource = resourceName
        guard let url = Bundle.main.url(forResource: resourceName, withExtension: "mp4") else {
            return
        }
        let item = AVPlayerItem(url: url)
        let queue = AVQueuePlayer()
        queue.isMuted = true
        queue.actionAtItemEnd = .advance
        let looper = AVPlayerLooper(player: queue, templateItem: item)

        let layer = AVPlayerLayer(player: queue)
        layer.videoGravity = .resizeAspectFill
        layer.frame = bounds
        self.layer?.sublayers?.forEach { $0.removeFromSuperlayer() }
        self.layer?.addSublayer(layer)

        self.player = queue
        self.looper = looper
        self.playerLayer = layer
        queue.play()
    }

    func stop() {
        player?.pause()
        playerLayer?.removeFromSuperlayer()
        playerLayer = nil
        looper = nil
        player = nil
    }
}
