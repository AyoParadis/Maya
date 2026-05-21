import AppKit
import SwiftUI

struct CarouselTimelineView: View {
    @Bindable var project: CarouselProject
    @Binding var currentTime: Double
    @Binding var isPlaying: Bool

    @State private var isScrubbing = false

    private let rowLabelWidth: CGFloat = 96
    private let rulerHeight: CGFloat = 20
    private let motionHeight: CGFloat = 60
    private let cardsHeight: CGFloat = 56

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
            TimelineToolbarIconButton(
                systemImage: isPlaying ? "pause.fill" : "play.fill",
                help: "Play/Pause (space)"
            ) {
                isPlaying.toggle()
            }

            TimelineTimeReadout(current: currentTime, total: project.totalDuration)

            if let card = project.selectedCard {
                Text(card.headline.isEmpty ? card.displayName : card.headline)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.82))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    private var rowLabels: some View {
        VStack(alignment: .leading, spacing: 4) {
            Color.clear.frame(height: rulerHeight)

            TimelineRowLabel(icon: "sparkles", title: "Motion", height: motionHeight)

            TimelineRowLabel(icon: "rectangle.stack", title: "Cards", height: cardsHeight)
        }
        .frame(width: rowLabelWidth, alignment: .leading)
    }

    private var tracks: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let duration = max(project.totalDuration, 0)
            let totalHeight = rulerHeight + motionHeight + cardsHeight + 8

            ZStack(alignment: .topLeading) {
                VStack(spacing: 4) {
                    TimelineRuler(duration: duration, width: width, height: rulerHeight)
                    CarouselMotionTrack(project: project, currentTime: $currentTime, height: motionHeight)
                    CarouselCardsTrack(project: project, currentTime: $currentTime, height: cardsHeight)
                }
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .local) { point in
                    seek(from: point.x, width: width)
                }

                if duration > 0 {
                    let x = CGFloat(currentTime / duration) * width
                    TimelinePlayhead(
                        height: totalHeight,
                        timeText: isScrubbing ? formatTimestamp(currentTime) : nil
                    )
                    .position(x: x, y: totalHeight / 2)
                    .gesture(
                        DragGesture(minimumDistance: 0, coordinateSpace: .named("carouselTracksSpace"))
                            .onChanged { value in
                                isScrubbing = true
                                seek(from: value.location.x, width: width)
                            }
                            .onEnded { _ in isScrubbing = false }
                    )
                }
            }
            .coordinateSpace(name: "carouselTracksSpace")
        }
        .frame(height: rulerHeight + motionHeight + cardsHeight + 8)
    }

    private func seek(from x: CGFloat, width: CGFloat) {
        guard project.totalDuration > 0 else { return }
        let progress = max(0, min(1, x / max(width, 1)))
        currentTime = project.totalDuration * Double(progress)
        project.selectCard(at: currentTime)
    }

}

private struct CarouselMotionTrack: View {
    @Bindable var project: CarouselProject
    @Binding var currentTime: Double
    let height: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .topLeading) {
                TimelineTrackBackground()

                ForEach(Array(project.cards.enumerated()), id: \.element.id) { index, card in
                    motionBlock(index: index, card: card, width: width)
                }
            }
            .frame(width: width, height: height)
        }
        .frame(height: height)
    }

    private func motionBlock(index: Int, card: CarouselCard, width: CGFloat) -> some View {
        let metrics = project.timelineMetrics(for: card)
        let x = CGFloat(metrics.startFraction) * width
        let blockWidth = max(36, CGFloat(metrics.durationFraction) * width)
        let isSelected = project.selectedCardID == card.id
        let motion = card.motionOverride ?? project.motionPreset

        return Button {
            project.select(card)
            currentTime = project.startTime(for: card.id)
        } label: {
            VStack(spacing: 2) {
                Image(systemName: motion.symbol)
                    .font(.system(size: 13, weight: .semibold))
                Text(motion.label)
                    .font(.system(size: 9, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            .foregroundStyle(isSelected ? .white : .white.opacity(0.82))
            .frame(width: blockWidth, height: height - 12)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(isSelected ? Color.white.opacity(0.16) : Color.white.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .stroke(isSelected ? Color.white.opacity(0.45) : Color.white.opacity(0.08), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .offset(x: x, y: 6)
    }
}

private struct CarouselCardsTrack: View {
    @Bindable var project: CarouselProject
    @Binding var currentTime: Double
    let height: CGFloat

    @State private var resizingCardID: UUID?
    @State private var resizeStartDuration: Double?

    private let minCardDuration = 0.5
    private let maxCardDuration = 8.0

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .topLeading) {
                TimelineTrackBackground(cornerRadius: 8, fillOpacity: 0.04)

                ForEach(Array(project.cards.enumerated()), id: \.element.id) { index, card in
                    cardBlock(index: index, card: card, width: width)
                }
            }
            .frame(width: width, height: height)
        }
        .frame(height: height)
    }

    private func cardBlock(index: Int, card: CarouselCard, width: CGFloat) -> some View {
        let duration = max(project.totalDuration, 0.001)
        let metrics = project.timelineMetrics(for: card)
        let x = CGFloat(metrics.startFraction) * width
        let blockWidth = max(44, CGFloat(metrics.durationFraction) * width)
        let isSelected = project.selectedCardID == card.id
        let trimColor = Color(red: 1.0, green: 0.82, blue: 0.10)

        return ZStack(alignment: .trailing) {
            ZStack(alignment: .leading) {
                if let imageURL = card.imageURL, let image = NSImage(contentsOf: imageURL) {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFill()
                        .frame(width: blockWidth, height: height)
                        .opacity(0.62)
                        .clipped()
                } else {
                    LinearGradient(
                        colors: [.white.opacity(0.14), .white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                }

                LinearGradient(
                    colors: [.black.opacity(0.72), .black.opacity(0.36)],
                    startPoint: .leading,
                    endPoint: .trailing
                )

                HStack(spacing: 6) {
                    Text("\(index + 1)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(.black.opacity(0.82))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(trimColor))
                    Text(card.headline.isEmpty ? card.displayName : card.headline)
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                        .shadow(color: .black.opacity(0.45), radius: 1, y: 1)
                    Spacer(minLength: 0)
                    Image(systemName: card.status.symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(card.status == .approved ? .green : .white.opacity(0.75))
                    Text(String(format: "%.1fs", card.duration))
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.8))
                }
                .padding(.horizontal, 8)
            }
            .frame(width: blockWidth, height: height)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? trimColor : trimColor.opacity(0.55), lineWidth: isSelected ? 3 : 2)
            )

            durationHandle(card: card, timelineWidth: width, timelineDuration: duration)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            project.select(card)
            currentTime = project.startTime(for: card.id)
        }
        .offset(x: x)
        .overlay(alignment: .topTrailing) {
            if resizingCardID == card.id {
                TimeTooltip(text: "\(String(format: "%.1fs", card.duration))")
                    .offset(x: 20, y: -30)
            }
        }
    }

    private func durationHandle(card: CarouselCard, timelineWidth: CGFloat, timelineDuration: Double) -> some View {
        RoundedRectangle(cornerRadius: 3)
            .fill(Color.white.opacity(0.85))
            .frame(width: 8, height: height + 6)
            .overlay(
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.black.opacity(0.55))
                    .frame(width: 2, height: height * 0.4)
            )
            .shadow(color: .black.opacity(0.35), radius: resizingCardID == card.id ? 6 : 2, y: 1)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        if resizingCardID != card.id {
                            resizingCardID = card.id
                            resizeStartDuration = card.duration
                            project.select(card)
                        }
                        guard let resizeStartDuration else { return }
                        let delta = (Double(value.translation.width) / Double(max(timelineWidth, 1))) * timelineDuration
                        card.duration = max(minCardDuration, min(maxCardDuration, resizeStartDuration + delta))
                        currentTime = project.startTime(for: card.id)
                    }
                    .onEnded { _ in
                        resizingCardID = nil
                        resizeStartDuration = nil
                        project.validate()
                    }
            )
            .help("Drag to adjust slide duration")
    }
}
