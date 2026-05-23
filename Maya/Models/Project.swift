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

    /// In/out points on the *source* video. Non-destructive: the underlying file is untouched.
    /// Together with `clipTimelineStart` they define an "edit": which portion of the source
    /// to play and where to place it on the project timeline.
    var trimStartTime: Double = 0
    var trimEndTime: Double = 0

    /// Where the trimmed clip sits on the project timeline. This is independent from
    /// `trimStartTime` — the user can grab the clip and slide it anywhere on the
    /// timeline without changing which source frames play. NLE-style.
    var clipTimelineStart: Double = 0

    /// Minimum length you can trim a clip down to. Mirrors Apple Photos' behavior.
    static let minTrimDuration: Double = 0.5

    var isExporting: Bool = false
    var exportProgress: Double = 0
    var lastExportError: String?

    var narrationScript: String = ""
    var narrationEngine: NarrationEngine = .defaultEngine
    var piperVoice: String = NarrationEngine.defaultEngine.defaultVoice
    var narrationEngineInstallationStatus: NarrationEngineInstallationStatus = .notInstalled
    var narrationAudioURL: URL?
    var narrationDisplayName: String?
    var isGeneratingNarration: Bool = false
    var isInstallingPiper: Bool = false
    var isCachingVoicePreviews: Bool = false
    var isPreviewingVoice: Bool = false
    var narrationMessage: String?

    var sourceAudioVolume: Double = 0 {
        didSet {
            sourceAudioVolume = max(0, min(sourceAudioVolume, 1))
            if sourceAudioVolume > 0.001 {
                sourceAudioVolumeBeforeMute = sourceAudioVolume
            }
            applySourceAudioVolume()
        }
    }

    var narrationAudioVolume: Double = 1 {
        didSet {
            narrationAudioVolume = max(0, min(narrationAudioVolume, 1))
        }
    }

    var isMuted: Bool {
        get { sourceAudioVolume <= 0.001 }
        set {
            if newValue {
                sourceAudioVolume = 0
            } else {
                sourceAudioVolume = max(sourceAudioVolumeBeforeMute, 0.5)
            }
        }
    }

    private var loopObserver: NSObjectProtocol?
    private var timeObserver: Any?
    private var sourceAudioVolumeBeforeMute: Double = 1

    deinit {
        if let o = loopObserver { NotificationCenter.default.removeObserver(o) }
        if let observer = timeObserver, let player = player {
            player.removeTimeObserver(observer)
        }
        Self.cleanupCachedSource(at: videoURL)
        NarrationService.cleanupGeneratedNarration(at: narrationAudioURL)
    }

    var durationSeconds: Double {
        let s = videoDuration.seconds
        return (s.isFinite && s > 0) ? s : 0
    }

    /// Length of the clip (after trim) in seconds.
    var clipDuration: Double {
        max(0, trimEndTime - trimStartTime)
    }

    /// Backwards-compat alias used by the toolbar and export.
    var trimmedDuration: Double { clipDuration }

    /// Right edge of the clip on the project timeline.
    var clipTimelineEnd: Double {
        clipTimelineStart + clipDuration
    }

    /// Length of the project timeline shown in the editor. Grows beyond the source duration
    /// only if the user has dragged the clip past the natural end.
    var timelineDuration: Double {
        max(durationSeconds, clipTimelineEnd)
    }

    /// True when the user has trimmed something off either end or shifted the clip.
    var isTrimmed: Bool {
        guard durationSeconds > 0 else { return false }
        return trimStartTime > 0.001
            || trimEndTime < durationSeconds - 0.001
            || clipTimelineStart > 0.001
    }

    /// Converts a project-timeline second to its source-video second. Outside the clip's
    /// timeline window the closest source edge is returned so seeks land on a renderable frame.
    func timelineToSource(_ t: Double) -> Double {
        if t <= clipTimelineStart { return trimStartTime }
        if t >= clipTimelineEnd { return trimEndTime }
        return trimStartTime + (t - clipTimelineStart)
    }

    /// Inverse of `timelineToSource`.
    func sourceToTimeline(_ s: Double) -> Double {
        clipTimelineStart + (s - trimStartTime)
    }

    func setTrimStart(_ t: Double) {
        let maxStart = max(0, trimEndTime - Self.minTrimDuration)
        trimStartTime = max(0, min(t, maxStart))
    }

    func setTrimEnd(_ t: Double) {
        let minEnd = min(durationSeconds, trimStartTime + Self.minTrimDuration)
        trimEndTime = max(minEnd, min(t, durationSeconds))
    }

    /// Clamps a timeline second into the clip's window.
    func clampedToClip(_ t: Double) -> Double {
        guard clipDuration > 0 else { return clipTimelineStart }
        if t < clipTimelineStart { return clipTimelineStart }
        if t > clipTimelineEnd { return clipTimelineEnd }
        return t
    }

    /// Looks up the segment under a *timeline* second. Returns nil if the timeline time
    /// lies outside the clip window (no source frame is playing there).
    func segment(containing timelineTime: Double) -> ZoomSegment? {
        guard timelineTime >= clipTimelineStart, timelineTime <= clipTimelineEnd else { return nil }
        let s = timelineToSource(timelineTime)
        return animations.first { s >= $0.startTime && s <= $0.endTime }
    }

    func canAddZoomSegment(at timelineTime: Double) -> Bool {
        proposedZoomSegment(at: timelineTime) != nil
    }

    /// Adds a zoom anchored at the given *timeline* second. Stored internally in source
    /// coords so the animation stays attached to the same source frame even if the clip
    /// is later moved or re-trimmed.
    @discardableResult
    func addZoomSegment(at timelineTime: Double) -> ZoomSegment? {
        guard var segment = proposedZoomSegment(at: timelineTime) else { return nil }
        segment = nonOverlappingZoomSegment(segment, excluding: segment.id) ?? segment
        animations.append(segment)
        selectedAnimationID = segment.id
        return segment
    }

    func updateZoomSegment(_ segment: ZoomSegment) {
        guard let idx = animations.firstIndex(where: { $0.id == segment.id }) else { return }
        guard var s = nonOverlappingZoomSegment(segment, excluding: segment.id) else { return }
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
        guard var placedCopy = nonOverlappingZoomSegment(
            copy,
            preferredStart: original.endTime + 0.1,
            excluding: nil
        ) else { return nil }
        placedCopy.normalize()
        animations.append(placedCopy)
        selectedAnimationID = placedCopy.id
        return placedCopy
    }

    func nonOverlappingZoomSegment(
        _ segment: ZoomSegment,
        preferredStart: Double? = nil,
        excluding excludedID: ZoomSegment.ID?
    ) -> ZoomSegment? {
        guard clipDuration >= ZoomSegment.durationRange.lowerBound else { return nil }
        var s = segment
        s.normalize()
        let lower = trimStartTime
        let upper = trimEndTime
        let maxDuration = min(s.duration, upper - lower, ZoomSegment.durationRange.upperBound)
        s.duration = max(ZoomSegment.durationRange.lowerBound, maxDuration)
        let start = preferredStart ?? s.startTime
        guard let placedStart = nearestAvailableZoomStart(
            preferredStart: start,
            duration: s.duration,
            excluding: excludedID,
            lowerBound: lower,
            upperBound: upper
        ) else { return nil }
        s.startTime = placedStart
        return s
    }

    private func proposedZoomSegment(at timelineTime: Double) -> ZoomSegment? {
        let duration = min(ZoomSegment.defaultDuration, max(clipDuration, 0))
        guard duration >= ZoomSegment.durationRange.lowerBound else { return nil }
        let latestTimelineStart = max(clipTimelineEnd - duration, clipTimelineStart)
        let clampedTimeline = max(clipTimelineStart, min(timelineTime, latestTimelineStart))
        let sourceStart = timelineToSource(clampedTimeline)
        var segment = ZoomSegment(
            startTime: sourceStart,
            duration: min(duration, max(trimEndTime - sourceStart, 0.4)),
            scale: ZoomSegment.defaultScale,
            focus: .center
        )
        segment.normalize()
        guard canPlaceZoomSegment(segment, excluding: nil) else { return nil }
        return segment
    }

    private func canPlaceZoomSegment(_ segment: ZoomSegment, excluding excludedID: ZoomSegment.ID?) -> Bool {
        let endTime = segment.startTime + segment.duration
        guard segment.startTime >= trimStartTime - 0.001, endTime <= trimEndTime + 0.001 else { return false }
        return !animations.contains { other in
            other.id != excludedID && rangesOverlap(segment.startTime, endTime, other.startTime, other.endTime)
        }
    }

    private func nearestAvailableZoomStart(
        preferredStart: Double,
        duration: Double,
        excluding excludedID: ZoomSegment.ID?,
        lowerBound: Double,
        upperBound: Double
    ) -> Double? {
        let sorted = animations
            .filter { $0.id != excludedID }
            .sorted { $0.startTime < $1.startTime }
        var gaps: [(start: Double, end: Double)] = []
        var cursor = lowerBound
        for segment in sorted {
            if segment.startTime > cursor {
                gaps.append((cursor, segment.startTime))
            }
            cursor = max(cursor, segment.endTime)
        }
        if cursor < upperBound {
            gaps.append((cursor, upperBound))
        }

        let viable = gaps.compactMap { gap -> (start: Double, end: Double)? in
            let latestStart = gap.end - duration
            return latestStart >= gap.start ? (gap.start, latestStart) : nil
        }
        guard !viable.isEmpty else { return nil }

        let candidate = viable
            .map { gap in max(gap.start, min(preferredStart, gap.end)) }
            .min { abs($0 - preferredStart) < abs($1 - preferredStart) }
        return candidate
    }

    private func rangesOverlap(_ aStart: Double, _ aEnd: Double, _ bStart: Double, _ bEnd: Double) -> Bool {
        aStart < bEnd - 0.001 && aEnd > bStart + 0.001
    }

    func toggleMute() {
        isMuted = !isMuted
    }

    private func applySourceAudioVolume() {
        player?.volume = Float(sourceAudioVolume)
        player?.isMuted = sourceAudioVolume <= 0.001
    }

    /// Seek to a project-timeline second. The player itself runs in source coords so we
    /// translate before issuing the seek.
    func seek(to timelineSeconds: Double) {
        guard let player else { return }
        let clamped = clampedToClip(timelineSeconds)
        let source = timelineToSource(clamped)
        let time = CMTime(seconds: source, preferredTimescale: 600)
        player.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
        currentSeconds = clamped
    }

    /// Loads a video. `url` must already be inside the app sandbox (use
    /// `Project.adoptIntoSandbox(_:)` first). Cleans up the previous working copy.
    func loadVideo(url: URL) async {
        let signpost = PerformanceMetrics.begin(.videoLoad, detail: url.lastPathComponent)
        let timer = WallClockTimer()
        defer {
            PerformanceMetrics.end(.videoLoad, id: signpost, detail: "\(timer.elapsedMilliseconds)ms")
        }

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
        newPlayer.volume = Float(sourceAudioVolume)
        newPlayer.isMuted = isMuted

        if let o = loopObserver { NotificationCenter.default.removeObserver(o) }
        loopObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self, weak newPlayer] _ in
            let target = self?.trimStartTime ?? 0
            let time = CMTime(seconds: target, preferredTimescale: 600)
            newPlayer?.seek(to: time, toleranceBefore: .zero, toleranceAfter: .zero)
            newPlayer?.play()
        }

        if let observer = timeObserver, let oldPlayer = self.player {
            oldPlayer.removeTimeObserver(observer)
        }

        self.videoURL = url
        self.videoNaturalSize = naturalSize
        self.videoDuration = duration
        self.player = newPlayer
        // Initialize trim to the full clip and place the clip at timeline 0 on every new video.
        let durSeconds = duration.seconds.isFinite ? duration.seconds : 0
        self.trimStartTime = 0
        self.trimEndTime = max(durSeconds, 0)
        self.clipTimelineStart = 0
        self.currentSeconds = 0
        self.isPlaying = true
        NarrationService.cleanupGeneratedNarration(at: narrationAudioURL)
        self.narrationAudioURL = nil
        self.narrationDisplayName = nil
        self.narrationMessage = nil

        // Now safe to remove the previous working copy.
        Self.cleanupCachedSource(at: previousURL)

        timeObserver = newPlayer.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 30),
            queue: .main
        ) { [weak self] time in
            guard let self else { return }
            let sourceTime = time.seconds
            // If the player crosses the trim-out point while playing, snap back to trim-in.
            if self.clipDuration > 0, sourceTime >= self.trimEndTime - 0.01 {
                let target = CMTime(seconds: self.trimStartTime, preferredTimescale: 600)
                self.player?.seek(to: target, toleranceBefore: .zero, toleranceAfter: .zero)
                self.currentSeconds = self.clipTimelineStart
            } else {
                self.currentSeconds = self.sourceToTimeline(sourceTime)
            }
        }

        newPlayer.play()
    }

    func togglePlayback() {
        guard let player else { return }
        if isPlaying || player.timeControlStatus == .playing {
            player.pause()
            isPlaying = false
        } else {
            // If the playhead drifted outside the clip, snap to clip-in (timeline coords).
            if currentSeconds < clipTimelineStart || currentSeconds >= clipTimelineEnd - 0.01 {
                seek(to: clipTimelineStart)
            }
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
