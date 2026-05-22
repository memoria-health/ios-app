import SwiftUI

/// Event card. Card background encodes type (terra-soft = safety,
/// sky-soft = routine). Card opacity encodes state (62% for opened,
/// 100% for unopened). CUSTOM pill appears only when `source == .custom`.
/// REVIEWED pill replaces the chevron in the footer when reviewed.
struct EventCard: View {
    let event: DetectionEvent

    private var cardBackground: Color {
        event.category == .safety ? NemaraColor.terraSoft : NemaraColor.skySoft
    }
    private var categoryBadgeColor: Color {
        event.category == .safety ? NemaraColor.terra : NemaraColor.sky
    }
    private var categoryLabel: String {
        event.category == .safety ? "SAFETY" : "ROUTINE"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(NemaraColor.card.opacity(0.55))
                    Image(systemName: event.iconName)
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(categoryBadgeColor)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        NemaraSolidPill(text: categoryLabel, background: categoryBadgeColor)
                        if event.source == .custom {
                            NemaraSolidPill(text: "CUSTOM", background: NemaraColor.terra)
                        }
                    }
                    Text(event.title)
                        .font(NemaraFont.serif(size: 17, weight: event.opened ? .regular : .semibold))
                        .kerning(-0.3)
                        .foregroundStyle(NemaraColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(event.location)
                        .font(NemaraFont.caption)
                        .foregroundStyle(NemaraColor.ink2)
                }
                Spacer()
            }
            .padding(14)

            Rectangle()
                .fill(NemaraColor.ink.opacity(0.08))
                .frame(height: 1)

            HStack(spacing: 8) {
                Text(event.time)
                    .font(NemaraFont.mono(size: 11, weight: .semibold))
                    .foregroundStyle(NemaraColor.ink2)
                Text("·").foregroundStyle(NemaraColor.ink.opacity(0.18))
                Text(event.ago.uppercased())
                    .font(NemaraFont.mono(size: 10, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(NemaraColor.ink3)
                Spacer()
                if event.reviewed {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(NemaraColor.ink3)
                        Text("REVIEWED")
                            .font(NemaraFont.mono(size: 9, weight: .bold))
                            .tracking(0.5)
                            .foregroundStyle(NemaraColor.ink3)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 4)
                    .background(NemaraColor.card.opacity(0.55))
                    .clipShape(Capsule(style: .continuous))
                } else {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(NemaraColor.ink3)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
        }
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.lg, style: .continuous))
        .opacity(event.opened ? 0.62 : 1)
    }
}

#Preview {
    let events = MockStore().events.values.first ?? []
    return ScrollView {
        VStack(spacing: 12) {
            ForEach(events) { ev in EventCard(event: ev) }
        }
        .padding()
    }
    .background(NemaraColor.paper)
}
