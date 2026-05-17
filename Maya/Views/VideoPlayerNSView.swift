import AVFoundation
import AppKit
import SwiftUI

struct VideoPlayerNSView: NSViewRepresentable {
    let player: AVPlayer?
    let cornerRadiusFraction: CGFloat

    func makeNSView(context: Context) -> PlayerHostView {
        let v = PlayerHostView()
        v.cornerRadiusFraction = cornerRadiusFraction
        v.player = player
        return v
    }

    func updateNSView(_ nsView: PlayerHostView, context: Context) {
        if nsView.player !== player { nsView.player = player }
        nsView.cornerRadiusFraction = cornerRadiusFraction
    }
}

final class PlayerHostView: NSView {
    private let playerLayer = AVPlayerLayer()

    var cornerRadiusFraction: CGFloat = 0 {
        didSet { needsLayout = true }
    }

    var player: AVPlayer? {
        didSet { playerLayer.player = player }
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = true
        playerLayer.videoGravity = .resizeAspectFill
        layer?.addSublayer(playerLayer)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        layer?.cornerRadius = bounds.width * cornerRadiusFraction
        CATransaction.commit()
    }
}
