import AVFoundation
import Foundation
import Observation
import SwiftUI

@Observable
final class Project {
    /// URL of the working copy inside the app's sandbox. The user's original file is never
    /// referenced after load — we hard-link (same volume) or copy it into our Caches dir so
    /// every subsequent read (preview, thumbnails, export) has unrestricted sandbox access
    /// from any thread. This sidesteps the entire security-scoped-resource dance, which is
    /// unreliable for drag-drop URLs across actor/queue boundaries.
    var videoURL: URL?
    /// Display name (the user's original file name) for UI labels.
    var displayName: String?
    var player: AVPlayer?
    var videoNaturalSize: CGSize = .zero
    var videoDuration: CMTime = .zero
    var currentSeconds: Double = 0
    var isPlaying: Bool = false

    var scale: CGFloat = 0.85
    var offset: CGSize = .zero
    var background: BackgroundOption = .gradient(GradientSpec.presets[0])
    var canvasAspect: CanvasAspectRatio = .square
    var shadow: PhoneShadow = PhoneShadow()

    /// Device picker state. We track model + color separately so switching models
    /// can gracefully fall back to that model's default color.
    var deviceModelID: String = DeviceModel.iPhone17Pro.id
    var deviceColorID: String = DeviceModel.iPhone17Pro.defaultColor.id

    /// Corner radius for the bare video, used when the active device is
    /// `.none` or `.generic`. Normalized to the screen's short side: 0 = sharp,
    /// 0.5 = fully rounded (stadium / circle).
    var bareCornerRadius: CGFloat = 0.15

    /// Stroke width of the generic device bezel, normalized to phone width
    /// (0 → no bezel, 0.1 → fat bezel).
    var bareBezelWidth: CGFloat = 0.025

    /// Color of the generic device bezel, stored as hex so it survives
    /// snapshot/export without bridging through NSColor on background queues.
    var bareBezelHex: String = "#000000"

    var deviceModel: DeviceModel {
        DeviceModel.model(id: deviceModelID) ?? .iPhone17Pro
    }

    var deviceColor: DeviceColor {
        deviceModel.color(id: deviceColorID) ?? deviceModel.defaultColor
    }

    var deviceFrame: DeviceFrame {
        deviceModel.frame(for: deviceColor)
    }

    func selectDeviceModel(_ model: DeviceModel) {
        deviceModelID = model.id
        if model.color(id: deviceColorID) == nil {
            deviceColorID = model.defaultColor.id
        }
    }

    func selectDeviceColor(_ color: DeviceColor) {
        guard deviceModel.color(id: color.id) != nil else { return }
        deviceColorID = color.id
    }

    var animations: [ZoomSegment] = []
    var selectedAnimationID: ZoomSegment.ID?

    var isExporting: Bool = false
    var exportProgress: Double = 0
    var lastExportError: String?

    var isMuted: Bool = true {
        didSet { player?.isMuted = isMuted }
    }

    private var loopObserver: NSObjectProtocol?
    private var timeObserver: Any?

    deinit {
        if let o = loopObserver { NotificationCenter.default.removeObserver(o) }
        if let observer = timeObserver, let player = player {
            player.removeTimeObserver(observer)
        }
        Self.cleanupCachedSource(at: videoURL)
    }

    var durationSeconds: Double {
        let s = videoDuration.seconds
        return (s.isFinite && s > 0) ? s : 0
    }

    func segment(containing time: Double) -> ZoomSegment? {
        animations.first { time >= $0.startTime && time <= $0.endTime }
    }

    func addZoomSegment(at time: Double) -> ZoomSegment {
        let dur = ZoomSegment.defaultDuration
        let clampedStart = max(0, min(time, max(durationSeconds - dur, 0)))
        var segment = ZoomSegment(
            startTime: clampedStart,
            duration: min(dur, max(durationSeconds - clampedStart, 0.4)),
            scale: ZoomSegment.defaultScale,
            focus: .center
        )
        segment.normalize()
        animations.append(segment)
        selectedAnimationID = segment.id
        return segment
    }

    func updateZoomSegment(_ segment: ZoomSegment) {
        guard let idx = animations.firstIndex(where: { $0.id == segment.id }) else { return }
        var s = segment
        s.normalize()
        animations[idx] = s
    }

    func removeZoomSegment(id: ZoomSegment.ID) {
        animations.removeAll { $0.id == id }
        if selectedAnimationID == id { selectedAnimationID = nil }
    }

    @discardableResult
    func duplicateZoomSegment(id: ZoomSegment.ID) -> ZoomSegment? {
        guard let original = animations.first(where: { $0.id == id }) else { return nil }
        var copy = original
        copy.id = UUID()
        copy.startTime = min(original.endTime + 0.1, max(durationSeconds - copy.duration, 0))
        copy.normalize()
        animations.append(copy)
        selectedAnimationID = copy.id
        return copy
    }

    func toggleMute() {
        isMuted.toggle()
    }

    func seek(to seconds: Double) {
        guard let player else { return }
        let clamped = max(0, min(seconds, durationSeconds))
        let time = CMTime(seconds: clamped, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        currentSeconds = clamped
    }

    /// Loads a video. `url` must already be inside the app sandbox (use
    /// `Project.adoptIntoSandbox(_:)` first). Cleans up the previous working copy.
    func loadVideo(url: URL) async {
        let previousURL = videoURL
        let asset = AVURLAsset(url: url)
        var naturalSize = CGSize.zero
        var duration = CMTime.zero
        if let track = try? await asset.loadTracks(withMediaType: .video).first {
            if let size = try? await track.load(.naturalSize) {
                naturalSize = size
            }
        }
        if let d = try? await asset.load(.duration) {
            duration = d
        }

        let item = AVPlayerItem(asset: asset)
        let newPlayer = AVPlayer(playerItem: item)
        newPlayer.isMuted = isMuted

        if let o = loopObserver { NotificationCenter.default.removeObserver(o) }
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak newPlayer] _ in
            newPlayer?.seek(to: .zero)
            newPlayer?.play()
        }

        if let observer = timeObserver, let oldPlayer = self.player {
            oldPlayer.removeTimeObserver(observer)
        }

        self.videoURL = url
        self.videoNaturalSize = naturalSize
        self.videoDuration = duration
        self.player = newPlayer
        self.currentSeconds = 0
        self.isPlaying = true

        // Now safe to remove the previous working copy.
        Self.cleanupCachedSource(at: previousURL)

        timeObserver = newPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30),
            queue: .main
        ) { [weak self] time in
            self?.currentSeconds = time.seconds
        }

        newPlayer.play()
    }

    func togglePlayback() {
        guard let player else { return }
        if isPlaying || player.timeControlStatus == .playing {
            player.pause()
            isPlaying = false
        } else {
            player.play()
            isPlaying = true
        }
    }

    func setPlayback(_ shouldPlay: Bool) {
        guard let player else { return }
        if shouldPlay {
            player.play()
        } else {
            player.pause()
        }
        isPlaying = shouldPlay
    }

    // MARK: - Sandbox file adoption
    //
    // macOS App Sandbox restricts file access by path. URLs obtained via drag-drop or
    // NSOpenPanel only carry usable scope on the thread / queue that received them, and
    // bookmark-with-security-scope creation is unreliable for drop URLs. The robust way
    // to handle this for any subsequent processing (preview, AVAssetReader on a background
    // thread, AVAssetExportSession, AVAssetImageGenerator…) is to bring the file *into*
    // the sandbox once, then operate on the local copy.
    //
    // We try a hard link first (instant, no extra disk usage, works on the same volume),
    // then fall back to a regular copy. The caller is responsible for opening the
    // security scope of the source URL before invoking this and stopping it afterward —
    // we don't bother capturing a bookmark because we no longer need post-callback access.

    static func cacheDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .cachesDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent("VideoSources", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func adoptIntoSandbox(_ source: URL) throws -> (sandboxURL: URL, displayName: String) {
        let originalName = source.lastPathComponent
        let cleanedName = originalName.replacingOccurrences(of: "/", with: "-")
        let dest = try cacheDirectory()
            .appendingPathComponent("\(UUID().uuidString)-\(cleanedName)")

        do {
            try FileManager.default.linkItem(at: source, to: dest)
        } catch {
            try FileManager.default.copyItem(at: source, to: dest)
        }
        return (dest, originalName)
    }

    static func cleanupCachedSource(at url: URL?) {
        guard let url else { return }
        let dir = (try? cacheDirectory().path) ?? ""
        guard !dir.isEmpty, url.path.hasPrefix(dir) else { return }
        try? FileManager.default.removeItem(at: url)
    }
}
