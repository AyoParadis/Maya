import SwiftUI

struct CarouselInspector: View {
    @Bindable var project: CarouselProject
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    selectedCardSection
                    Divider()
                    planSection
                }
                .padding(18)
            }
        }
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("Inspector")
                    .font(.headline)
                Text("Carousel slide details")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .help("Close inspector")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var selectedCardSection: some View {
        if let card = project.selectedCard {
            @Bindable var card = card
            VStack(alignment: .leading, spacing: 12) {
                Text("Selected Card").font(.headline)
                HStack {
                    Label(card.status.label, systemImage: card.status.symbol)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(card.status == .approved ? .green : .secondary)
                    Spacer()
                    Text(card.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                TextField("Role", text: $card.role)
                TextField("Badge", text: $card.badge)
                TextField("Headline", text: $card.headline, axis: .vertical)
                    .lineLimit(2...4)
                TextField("Subtitle", text: $card.subtitle, axis: .vertical)
                    .lineLimit(2...4)
                TextField("CTA", text: $card.cta)
                TextField("Visual prompt", text: $card.visualPrompt, axis: .vertical)
                    .lineLimit(2...5)
                if !card.rationale.isEmpty {
                    Text(card.rationale)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(nsColor: .controlBackgroundColor))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                Picker("Motion", selection: Binding(
                    get: { card.motionOverride ?? project.motionPreset },
                    set: { card.motionOverride = $0 }
                )) {
                    ForEach(CarouselMotionPreset.allCases) { motion in
                        Text(motion.label).tag(motion)
                    }
                }
                HStack {
                    Text("Duration")
                    Spacer()
                    Text("\(card.duration, specifier: "%.1f")s")
                        .foregroundStyle(.secondary)
                        .font(.caption.monospacedDigit())
                }
                Slider(value: $card.duration, in: 0.5...8.0, step: 0.1)
                    .tint(.gray)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("Focal X")
                        Spacer()
                        Text("\(card.focalPoint.x, specifier: "%.2f")")
                            .foregroundStyle(.secondary)
                            .font(.caption.monospacedDigit())
                    }
                    Slider(
                        value: Binding(
                            get: { card.focalPoint.x },
                            set: { card.focalPoint.x = max(0, min(1, $0)) }
                        ),
                        in: 0...1,
                        step: 0.01
                    )
                    .tint(.gray)
                    HStack {
                        Text("Focal Y")
                        Spacer()
                        Text("\(card.focalPoint.y, specifier: "%.2f")")
                            .foregroundStyle(.secondary)
                            .font(.caption.monospacedDigit())
                    }
                    Slider(
                        value: Binding(
                            get: { card.focalPoint.y },
                            set: { card.focalPoint.y = max(0, min(1, $0)) }
                        ),
                        in: 0...1,
                        step: 0.01
                    )
                    .tint(.gray)
                }
                HStack {
                    StudioSmallActionButton(title: "Duplicate", icon: "square.on.square") {
                        project.duplicateSelectedCard()
                    }
                    StudioSmallActionButton(title: "Delete", icon: "trash", isDestructive: true) {
                        project.removeSelectedCard()
                    }
                }
            }
            .textFieldStyle(.roundedBorder)
            .onChange(of: card.headline) { _, _ in project.validate() }
            .onChange(of: card.subtitle) { _, _ in project.validate() }
            .onChange(of: card.cta) { _, _ in project.validate() }
            .onChange(of: card.visualPrompt) { _, _ in project.validate() }
        } else {
            Text("Select a card to edit copy, motion, and timing.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    private var planSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Plan").font(.headline)
            if let plan = project.plan {
                Text(plan.rationale)
                    .font(.callout)
                ForEach(plan.cards.prefix(8)) { card in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(card.role)
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Label(card.status.label, systemImage: card.status.symbol)
                                .labelStyle(.iconOnly)
                                .foregroundStyle(card.status == .approved ? .green : .secondary)
                        }
                        Text(card.reason)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(nsColor: .controlBackgroundColor))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
            } else {
                Text("Create an outline to see slide roles and rationale.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
