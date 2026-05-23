import SwiftUI

struct NarratedImagesTimelineView: View {
    @Bindable var project: NarratedImageProject
    @Binding var currentTime: Double
    @Binding var isPlaying: Bool

    private let rowLabelWidth: CGFloat = 96
    private let rulerHeight: CGFloat = 20
    private let captionsHeight: CGFloat = 44
    private let voiceoverHeight: CGFloat = 44
    private let scenesHeight: CGFloat = 56

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider().opacity(0.4)
            HStack(alignment: .top, spacing: 12) {
                rowLabels
                tracks
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.black.opacity(0.35))
    }

    private var toolbar: some View {
        HStack(spacing: 12) {
            TimelineToolbarIconButton(systemImage: isPlaying ? "pause.fill" : "play.fill", help: "Play/Pause") {
                isPlaying.toggle()
            }
            TimelineTimeReadout(current: currentTime, total: project.totalDuration)
            if let scene = project.selectedScene {
                Text(scene.displayName)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var rowLabels: some View {
        VStack(alignment: .leading, spacing: 4) {
            Color.clear.frame(height: rulerHeight)
            TimelineRowLabel(icon: "captions.bubble", title: "Captions", height: captionsHeight)
            TimelineRowLabel(icon: "waveform", title: "Voiceover", height: voiceoverHeight)
            TimelineRowLabel(icon: "photo.stack", title: "Scenes", height: scenesHeight)
        }
        .frame(width: rowLabelWidth, alignment: .leading)
    }

    private var tracks: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let duration = max(project.totalDuration, 0)
            let totalHeight = rulerHeight + captionsHeight + voiceoverHeight + scenesHeight + 12
            ZStack(alignment: .topLeading) {
                VStack(spacing: 4) {
                    TimelineRuler(duration: duration, width: width, height: rulerHeight)
                    captionTrack(width: width)
                    voiceoverTrack(width: width)
                    scenesTrack(width: width)
                }
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .local) { point in
                    seek(from: point.x, width: width)
                }

                if duration > 0 {
                    TimelinePlayhead(height: totalHeight, timeText: nil)
                        .position(x: CGFloat(currentTime / duration) * width, y: totalHeight / 2)
                        .gesture(
                            DragGesture(minimumDistance: 0, coordinateSpace: .named("narratedTracksSpace"))
                                .onChanged { value in seek(from: value.location.x, width: width) }
                        )
                }
            }
            .coordinateSpace(name: "narratedTracksSpace")
        }
        .frame(height: rulerHeight + captionsHeight + voiceoverHeight + scenesHeight + 12)
    }

    private func captionTrack(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            TimelineTrackBackground(cornerRadius: 8, fillOpacity: 0.04)
            ForEach(project.scenes) { scene in
                let metrics = project.timelineMetrics(for: scene)
                ForEach(scene.captionBeats) { beat in
                    let start = metrics.start + beat.startTime
                    let end = metrics.start + min(beat.endTime, metrics.duration)
                    let x = CGFloat(start / max(project.totalDuration, 0.001)) * width
                    let blockWidth = max(24, CGFloat(max(0.1, end - start) / max(project.totalDuration, 0.001)) * width)
                    CaptionBeatTimelineBlock(
                        project: project,
                        scene: scene,
                        beat: beat,
                        width: blockWidth,
                        height: captionsHeight - 8,
                        trackWidth: width
                    )
                        .offset(x: x, y: 4)
                }
            }
        }
        .frame(height: captionsHeight)
    }

    private func voiceoverTrack(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            TimelineTrackBackground(cornerRadius: 8, fillOpacity: 0.04)
            ForEach(Array(project.scenes.enumerated()), id: \.element.id) { index, scene in
                if scene.narrationAudioURL != nil {
                    let metrics = project.timelineMetrics(for: scene)
                    let blockWidth = max(44, CGFloat(metrics.durationFraction) * width)
                    Button {
                        select(scene)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "waveform")
                            Text("\(index + 1)")
                            Text(scene.narrationAudioDuration.map { String(format: "%.1fs", $0) } ?? "audio")
                            Spacer()
                        }
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .frame(width: blockWidth, height: voiceoverHeight - 8)
                        .background(Color(red: 0.34, green: 0.47, blue: 1.0).opacity(0.52), in: RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                    .offset(x: CGFloat(metrics.startFraction) * width, y: 4)
                }
            }
        }
        .frame(height: voiceoverHeight)
    }

    private func scenesTrack(width: CGFloat) -> some View {
        ZStack(alignment: .topLeading) {
            TimelineTrackBackground(cornerRadius: 8, fillOpacity: 0.04)
            ForEach(Array(project.scenes.enumerated()), id: \.element.id) { index, scene in
                let metrics = project.timelineMetrics(for: scene)
                let blockWidth = max(44, CGFloat(metrics.durationFraction) * width)
                let isSelected = project.selectedSceneID == scene.id
                Button {
                    select(scene)
                } label: {
                    HStack(spacing: 6) {
                        Text("\(index + 1)")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background(Capsule().fill(Color.yellow))
                            .foregroundStyle(.black)
                        Text(scene.displayName)
                            .font(.system(size: 11, weight: .semibold, design: .rounded))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Spacer()
                        Text(String(format: "%.1fs", scene.duration))
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.white.opacity(0.8))
                    }
                    .padding(.horizontal, 8)
                    .frame(width: blockWidth, height: scenesHeight)
                    .background(Color.black.opacity(0.42), in: RoundedRectangle(cornerRadius: 8))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(isSelected ? Color.yellow : Color.yellow.opacity(0.55), lineWidth: isSelected ? 3 : 2)
                    )
                }
                .buttonStyle(.plain)
                .offset(x: CGFloat(metrics.startFraction) * width)
            }
        }
        .frame(height: scenesHeight)
    }

    private func seek(from x: CGFloat, width: CGFloat) {
        guard project.totalDuration > 0 else { return }
        let progress = max(0, min(1, x / max(width, 1)))
        currentTime = project.totalDuration * Double(progress)
        project.selectScene(at: currentTime)
    }

    private func select(_ scene: NarratedImageScene) {
        project.select(scene)
        currentTime = project.startTime(for: scene.id)
    }
}

private struct CaptionBeatTimelineBlock: View {
    @Bindable var project: NarratedImageProject
    @Bindable var scene: NarratedImageScene
    let beat: NarratedCaptionBeat
    let width: CGFloat
    let height: CGFloat
    let trackWidth: CGFloat

    @State private var startDragValue: Double?
    @State private var endDragValue: Double?

    var body: some View {
        let isSelected = scene.selectedCaptionBeatID == beat.id
        ZStack {
            Text(beat.text)
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .frame(width: width, height: height, alignment: .leading)
                .background(Color.white.opacity(isSelected ? 0.2 : 0.12), in: RoundedRectangle(cornerRadius: 7))
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(isSelected ? Color.yellow.opacity(0.95) : Color.white.opacity(0.12), lineWidth: isSelected ? 2 : 1)
                )

            HStack {
                trimHandle(edge: .start)
                Spacer(minLength: 0)
                trimHandle(edge: .end)
            }
            .frame(width: width, height: height)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            project.select(scene)
            scene.selectedCaptionBeatID = beat.id
        }
    }

    private func trimHandle(edge: CaptionTrimEdge) -> some View {
        Capsule()
            .fill(Color.white.opacity(0.82))
            .frame(width: 5, height: max(20, height - 10))
            .padding(.horizontal, 3)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        project.select(scene)
                        scene.selectedCaptionBeatID = beat.id
                        let secondsPerPoint = project.totalDuration / Double(max(trackWidth, 1))
                        let delta = Double(value.translation.width) * secondsPerPoint
                        switch edge {
                        case .start:
                            if startDragValue == nil { startDragValue = beat.startTime }
                            project.updateCaptionBeatTiming(scene: scene, beatID: beat.id, start: (startDragValue ?? beat.startTime) + delta)
                        case .end:
                            if endDragValue == nil { endDragValue = beat.endTime }
                            project.updateCaptionBeatTiming(scene: scene, beatID: beat.id, end: (endDragValue ?? beat.endTime) + delta)
                        }
                    }
                    .onEnded { _ in
                        startDragValue = nil
                        endDragValue = nil
                    }
            )
            .help(edge == .start ? "Drag to trim caption start" : "Drag to trim caption end")
    }
}

private enum CaptionTrimEdge {
    case start
    case end
}
