import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct CarouselTimelineView: View {
    @Bindable var project: CarouselProject
    @Binding var currentTime: Double
    @Binding var isPlaying: Bool

    @State private var isScrubbing = false

    private let rowLabelWidth: CGFloat = 96
    private let rulerHeight: CGFloat = 20
    private let motionHeight: CGFloat = 60
    private let voiceoverHeight: CGFloat = 44
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

            TimelineRowLabel(icon: "waveform", title: "Voiceover", height: voiceoverHeight)

            TimelineRowLabel(icon: "rectangle.stack", title: "Cards", height: cardsHeight)
        }
        .frame(width: rowLabelWidth, alignment: .leading)
    }

    private var tracks: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let duration = max(project.totalDuration, 0)
            let totalHeight = rulerHeight + motionHeight + voiceoverHeight + cardsHeight + 12

            ZStack(alignment: .topLeading) {
                VStack(spacing: 4) {
                    TimelineRuler(duration: duration, width: width, height: rulerHeight)
                    CarouselMotionTrack(project: project, currentTime: $currentTime, height: motionHeight)
                    CarouselVoiceoverTrack(project: project, currentTime: $currentTime, height: voiceoverHeight)
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
        .frame(height: rulerHeight + motionHeight + voiceoverHeight + cardsHeight + 12)
    }

    private func seek(from x: CGFloat, width: CGFloat) {
        guard project.totalDuration > 0 else { return }
        let progress = max(0, min(1, x / max(width, 1)))
        currentTime = project.totalDuration * Double(progress)
        project.selectCard(at: currentTime)
    }

}

private struct CarouselVoiceoverTrack: View {
    @Bindable var project: CarouselProject
    @Binding var currentTime: Double
    let height: CGFloat

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            ZStack(alignment: .topLeading) {
                TimelineTrackBackground(cornerRadius: 8, fillOpacity: 0.04)

                ForEach(Array(project.cards.enumerated()), id: \.element.id) { index, card in
                    if card.narrationAudioURL != nil {
                        voiceBlock(index: index, card: card, width: width)
                    }
                }
            }
            .frame(width: width, height: height)
        }
        .frame(height: height)
    }

    private func voiceBlock(index: Int, card: CarouselCard, width: CGFloat) -> some View {
        let metrics = project.timelineMetrics(for: card)
        let x = CGFloat(metrics.startFraction) * width
        let blockWidth = max(44, CGFloat(metrics.durationFraction) * width)
        let isSelected = project.selectedCardID == card.id
        let color = Color(red: 0.34, green: 0.47, blue: 1.0)

        return ZStack(alignment: .trailing) {
            Button {
                select(card)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .font(.system(size: 11, weight: .semibold))
                    Text("\(index + 1)")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                    Text(card.narrationAudioDuration.map { String(format: "%.1fs", $0) } ?? "audio")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .lineLimit(1)
                    Spacer(minLength: 20)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .frame(width: blockWidth, height: height - 8)
                .background(
                    RoundedRectangle(cornerRadius: 7)
                        .fill(isSelected ? color.opacity(0.72) : color.opacity(0.48))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7)
                        .stroke(isSelected ? Color.white.opacity(0.55) : color.opacity(0.75), lineWidth: isSelected ? 2 : 1)
                )
            }
            .buttonStyle(.plain)

            TimelineBlockMenu {
                voiceoverMenuContent(for: card)
            }
            .padding(.trailing, 5)
        }
        .offset(x: x, y: 4)
        .contextMenu {
            voiceoverMenuContent(for: card)
        }
        .help(card.narrationScript.isEmpty ? card.displayName : card.narrationScript)
    }

    private func select(_ card: CarouselCard) {
        project.select(card)
        currentTime = project.startTime(for: card.id)
    }

    @ViewBuilder
    private func voiceoverMenuContent(for card: CarouselCard) -> some View {
        Button {
            select(card)
        } label: {
            Label("Select slide", systemImage: "cursorarrow.click")
        }
        Button {
            select(card)
        } label: {
            Label("Reveal slide", systemImage: "scope")
        }
        Divider()
        Button(role: .destructive) {
            project.removeVoiceover(for: card.id)
        } label: {
            Label("Remove voiceover", systemImage: "waveform.slash")
        }
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

        return ZStack(alignment: .topTrailing) {
            Button {
                select(card)
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

            TimelineBlockMenu {
                motionMenuContent(for: card)
            }
            .padding(.trailing, 5)
            .padding(.top, 7)
        }
        .offset(x: x, y: 6)
        .contextMenu {
            motionMenuContent(for: card)
        }
    }

    private func select(_ card: CarouselCard) {
        project.select(card)
        currentTime = project.startTime(for: card.id)
    }

    @ViewBuilder
    private func motionMenuContent(for card: CarouselCard) -> some View {
        Button {
            select(card)
        } label: {
            Label("Select slide", systemImage: "cursorarrow.click")
        }
        Divider()
        ForEach(CarouselMotionPreset.allCases) { preset in
            Button {
                card.motionOverride = preset
                project.validate()
            } label: {
                Label(preset.label, systemImage: preset.symbol)
            }
        }
        Divider()
        Button {
            card.motionOverride = nil
            project.validate()
        } label: {
            Label("Reset to project default", systemImage: "arrow.counterclockwise")
        }
    }
}

private struct CarouselCardsTrack: View {
    @Bindable var project: CarouselProject
    @Binding var currentTime: Double
    let height: CGFloat

    @State private var resizingCardID: UUID?
    @State private var resizeStartDuration: Double?
    @State private var draggingCardID: UUID?

    private let minCardDuration = 0.5
    private let maxCardDuration = 30.0

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
                if let imageURL = card.imageURL {
                    CachedImageView(url: imageURL, maxPixelSize: 420) {
                        Color.black.opacity(0.32)
                    }
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
                    Spacer(minLength: 20)
                    Image(systemName: card.status.symbol)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.75))
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

            TimelineBlockMenu {
                cardMenuContent(for: card, index: index)
            }
            .padding(.trailing, 12)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            select(card)
        }
        .contextMenu {
            cardMenuContent(for: card, index: index)
        }
        .onDrag {
            draggingCardID = card.id
            project.select(card)
            return NSItemProvider(object: card.id.uuidString as NSString)
        } preview: {
            Text(card.headline.isEmpty ? card.displayName : card.headline)
                .font(.caption.weight(.semibold))
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 6))
                .foregroundStyle(.white)
        }
        .onDrop(
            of: [.text],
            delegate: CarouselCardReorderDropDelegate(
                project: project,
                targetCardID: card.id,
                currentTime: $currentTime,
                draggingCardID: $draggingCardID
            )
        )
        .opacity(draggingCardID == card.id ? 0.72 : 1)
        .scaleEffect(draggingCardID == card.id ? 0.985 : 1)
        .animation(.easeInOut(duration: 0.12), value: draggingCardID)
        .offset(x: x)
        .overlay(alignment: .topTrailing) {
            if resizingCardID == card.id {
                TimeTooltip(text: "\(String(format: "%.1fs", card.duration))")
                    .offset(x: 20, y: -30)
            }
        }
    }

    private func select(_ card: CarouselCard) {
        project.select(card)
        currentTime = project.startTime(for: card.id)
    }

    @ViewBuilder
    private func cardMenuContent(for card: CarouselCard, index: Int) -> some View {
        Button {
            select(card)
        } label: {
            Label("Select slide", systemImage: "cursorarrow.click")
        }
        Divider()
        Button {
            project.moveCardEarlier(id: card.id)
            currentTime = project.startTime(for: card.id)
        } label: {
            Label("Move earlier", systemImage: "arrow.left")
        }
        .disabled(index == 0)

        Button {
            project.moveCardLater(id: card.id)
            currentTime = project.startTime(for: card.id)
        } label: {
            Label("Move later", systemImage: "arrow.right")
        }
        .disabled(index >= project.cards.count - 1)
        Divider()
        Button {
            project.duplicateCard(id: card.id)
            if let id = project.selectedCardID {
                currentTime = project.startTime(for: id)
            }
        } label: {
            Label("Duplicate slide", systemImage: "square.on.square")
        }
        if card.narrationAudioURL != nil {
            Button(role: .destructive) {
                project.removeVoiceover(for: card.id)
            } label: {
                Label("Remove voiceover", systemImage: "waveform.slash")
            }
        }
        Button(role: .destructive) {
            project.removeCard(id: card.id)
            if let id = project.selectedCardID {
                currentTime = project.startTime(for: id)
            } else {
                currentTime = 0
            }
        } label: {
            Label("Delete slide", systemImage: "trash")
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

private struct TimelineBlockMenu<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        Menu {
            content()
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.white.opacity(0.9))
                .frame(width: 22, height: 22)
                .background(Color.black.opacity(0.28), in: Circle())
                .overlay(Circle().stroke(Color.white.opacity(0.12), lineWidth: 1))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Timeline actions. Control-click or two-finger click a timeline block to open the same menu.")
    }
}

private struct CarouselCardReorderDropDelegate: DropDelegate {
    let project: CarouselProject
    let targetCardID: UUID
    @Binding var currentTime: Double
    @Binding var draggingCardID: UUID?

    func dropEntered(info: DropInfo) {
        guard let sourceID = draggingCardID, sourceID != targetCardID else { return }
        withAnimation(.easeInOut(duration: 0.16)) {
            project.moveCard(from: sourceID, toPositionOf: targetCardID)
            currentTime = project.startTime(for: sourceID)
        }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        DropProposal(operation: .move)
    }

    func performDrop(info: DropInfo) -> Bool {
        draggingCardID = nil
        return true
    }

    func dropExited(info: DropInfo) {}
}
