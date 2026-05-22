import SwiftUI

/// Step 1 of 2 of the event review flow. Shows the title block, a video
/// clip (safety only), and Nemara's VLM-written narrative of what it
/// saw. Tapping "Review this event →" advances to `EventReviewView`.
struct EventDetailView: View {
    let event: DetectionEvent
    let patientId: UUID
    @Environment(\.dismiss) private var dismiss

    private var tone: Color {
        event.category == .safety ? NemaraColor.terra : NemaraColor.sky
    }
    private var toneSoft: Color {
        event.category == .safety ? NemaraColor.terraSoft : NemaraColor.skySoft
    }
    private var categoryLabel: String {
        event.category == .safety ? "SAFETY" : "ROUTINE"
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    titleBlock
                    if event.hasClip { clipView }
                    narrativeCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
                .padding(.top, 6)
            }

            footer
        }
        .background(NemaraColor.paper)
        .navigationTitle("Event detail")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text("1 / 2")
                    .font(NemaraFont.mono(size: 10, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(NemaraColor.ink3)
            }
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(NemaraColor.ink)
                }
            }
        }
    }

    // MARK: - sections

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(toneSoft)
                    Image(systemName: event.iconName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tone)
                }
                .frame(width: 28, height: 28)
                Text(categoryLabel)
                    .font(NemaraFont.mono(size: 10, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(tone)
            }
            Text(event.title)
                .font(NemaraFont.title1)
                .kerning(-0.8)
                .foregroundStyle(NemaraColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(event.location) · \(event.time)")
                .font(NemaraFont.bodySmall)
                .foregroundStyle(NemaraColor.ink2)
        }
    }

    private var clipView: some View {
        ZStack {
            NemaraCamFeedPlaceholder(hue: 30)
            Image(systemName: "play.fill")
                .font(.system(size: 18, weight: .black))
                .foregroundStyle(NemaraColor.terraInk)
                .frame(width: 52, height: 52)
                .background(NemaraColor.ink.opacity(0.55))
                .clipShape(Circle())

            VStack {
                Spacer()
                HStack {
                    Text("CAM 02 · \(event.location.uppercased())")
                        .font(NemaraFont.mono(size: 9, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(NemaraColor.terraInk)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(NemaraColor.ink.opacity(0.7))
                        .clipShape(Capsule(style: .continuous))
                    Spacer()
                    Text("0:14")
                        .font(NemaraFont.mono(size: 9, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(NemaraColor.terraInk)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(NemaraColor.ink.opacity(0.7))
                        .clipShape(Capsule(style: .continuous))
                }
            }
            .padding(8)
        }
        .aspectRatio(16/9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: NemaraRadius.lg, style: .continuous)
                .strokeBorder(NemaraColor.line, lineWidth: 1)
        )
    }

    private var narrativeCard: some View {
        NemaraCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NemaraColor.ink3)
                    NemaraEyebrow("WHAT NEMARA SAW")
                }
                Text(event.narrative)
                    .font(NemaraFont.bodySmallStrong.weight(.regular))
                    .foregroundStyle(NemaraColor.ink)
                    .lineSpacing(5)
            }
        }
    }

    private var footer: some View {
        HStack {
            NavigationLink {
                EventReviewView(event: event, patientId: patientId)
            } label: {
                Text("Review this event →")
                    .font(NemaraFont.sans(size: 16, weight: .semibold))
                    .tracking(-0.1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .foregroundStyle(NemaraColor.actionInk)
                    .background(NemaraColor.action)
                    .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(NemaraColor.paper)
        .overlay(NemaraColor.line.frame(height: 1), alignment: .top)
    }
}

#Preview {
    let env = AppEnvironment(auth: MockAuthService(), mockStore: MockStore())
    let pid = env.mockStore.patients[0].id
    return NavigationStack {
        EventDetailView(event: env.mockStore.events[pid]![0], patientId: pid)
    }
    .environment(env)
}
