import SwiftUI

/// Sheet shown the first time a caregiver toggles "Daily email summary"
/// on. Renders a mock of the email Nemara would send so they can decide
/// before they commit. Two CTAs at the bottom: "Not now" (off-ramp) and
/// "Send me these" (primary).
struct DailySummaryPreviewView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var env

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    intro
                    emailMock
                    includedList
                    Text("You can turn the summary off any time, or change which patients it covers, from Settings.")
                        .font(NemaraFont.caption)
                        .foregroundStyle(NemaraColor.ink3)
                        .lineSpacing(2)
                        .padding(.horizontal, 2)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            footer
        }
        .background(NemaraColor.paper)
    }

    // MARK: - sections

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(NemaraColor.ink)
            }
            .buttonStyle(.plain)
            Spacer()
            NemaraEyebrow("SAMPLE")
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            NemaraEyebrow("BEFORE YOU TURN IT ON", color: NemaraColor.terra)
            Text("Here's what we'd send.")
                .font(NemaraFont.title1)
                .foregroundStyle(NemaraColor.ink)
                .kerning(-0.8)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var emailMock: some View {
        VStack(spacing: 0) {
            // header strip
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    NemaraMark(size: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text("Nemara")
                                .font(NemaraFont.captionStrong)
                                .foregroundStyle(NemaraColor.ink)
                            Text("hello@nemara.app")
                                .font(NemaraFont.monoSmall)
                                .foregroundStyle(NemaraColor.ink3)
                        }
                        Text("to \(env.auth.currentCaregiver?.email ?? "you@home.com") · Wed 7:30 AM")
                            .font(NemaraFont.caption)
                            .foregroundStyle(NemaraColor.ink3)
                    }
                }
                Text("Maggie's day · Wed May 21")
                    .font(NemaraFont.title3)
                    .foregroundStyle(NemaraColor.ink)
                    .kerning(-0.2)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NemaraColor.paperDim)
            .overlay(NemaraColor.line.frame(height: 1), alignment: .bottom)

            // body
            VStack(alignment: .leading, spacing: 10) {
                Text("Maggie had a calm day. She woke around 7:30, had tea and toast in the kitchen, and settled into the living room with the radio on for most of the morning.")
                    .font(NemaraFont.bodySmall)
                    .foregroundStyle(NemaraColor.ink)
                    .lineSpacing(5)
                Text("She had lunch around 12:15 and napped on the couch for about an hour after. Around 4 she paced for a few minutes, then settled herself by 5 with the news. She was back in bed by 9:15.")
                    .font(NemaraFont.bodySmall)
                    .foregroundStyle(NemaraColor.ink)
                    .lineSpacing(5)

                flaggedCallout
                    .padding(.top, 4)

                Text("One thing we've noticed: she's been waking about 20 minutes earlier this week. Could be the longer days.")
                    .font(NemaraFont.bodySmall)
                    .foregroundStyle(NemaraColor.ink2)
                    .lineSpacing(5)
                    .padding(.top, 4)

                Text("We'll write again tomorrow.")
                    .font(NemaraFont.caption.italic())
                    .foregroundStyle(NemaraColor.ink3)
                    .padding(.top, 4)
            }
            .padding(16)

            // footer cue
            HStack(spacing: 6) {
                Image(systemName: "eye")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(NemaraColor.ink3)
                Text("Open Nemara for the full timeline")
                    .font(NemaraFont.monoSmall)
                    .foregroundStyle(NemaraColor.ink3)
                Spacer()
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .overlay(NemaraColor.line.frame(height: 1), alignment: .top)
        }
        .background(NemaraColor.card)
        .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: NemaraRadius.lg, style: .continuous)
                .strokeBorder(NemaraColor.line, lineWidth: 1)
        )
    }

    private var flaggedCallout: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("WE FLAGGED ONE THING")
                .font(NemaraFont.mono(size: 9.5, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(NemaraColor.terra)
            Text("A possible fall around 2:14 PM in the living room. She was up within a minute and seemed fine, but worth a quick look. [Review](https://nemara.app)")
                .font(NemaraFont.bodySmall)
                .foregroundStyle(NemaraColor.ink)
                .lineSpacing(4)
                .tint(NemaraColor.terra)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(NemaraColor.terraSoft)
        .overlay(
            Rectangle()
                .fill(NemaraColor.terra)
                .frame(width: 3)
                .frame(maxHeight: .infinity),
            alignment: .leading
        )
        .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous))
    }

    private var includedList: some View {
        VStack(alignment: .leading, spacing: 8) {
            NemaraEyebrow("WHAT'S INCLUDED")
            ForEach([
                "The shape of her day · waking, meals, settling in",
                "Anything we flagged for you — with a link to review",
                "Gentle shifts from her usual pattern",
            ], id: \.self) { line in
                HStack(spacing: 10) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .fill(NemaraColor.action)
                            .frame(width: 18, height: 18)
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(NemaraColor.actionInk)
                    }
                    Text(line)
                        .font(NemaraFont.bodySmall)
                        .foregroundStyle(NemaraColor.ink)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            NemaraButton("Not now", variant: .ghost, block: true) { dismiss() }
            NemaraButton("Send me these", variant: .primary, block: true) { dismiss() }
                .frame(maxWidth: .infinity)
                .layoutPriority(1)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(NemaraColor.paper)
        .overlay(NemaraColor.line.frame(height: 1), alignment: .top)
    }
}

#Preview {
    DailySummaryPreviewView()
        .environment(AppEnvironment.preview())
}
