import SwiftUI

/// Combined feedback / share / contact screen. Pushed from
/// PatientSettings's "Feedback & support" row. Self-contained — no
/// nested navigation.
struct FeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var rating: Int = 4
    @State private var whatsWorking: String = "The morning summary email is the first thing I open. It's calm and short."
    @State private var whatsFrustrating: String = ""
    @State private var category: String? = "Daily summary"
    @State private var includeContext: Bool = true

    private let categories = ["Detection", "Live feed", "Alerts", "Daily summary", "Settings", "Something else"]
    private let socials: [(label: String, icon: String)] = [
        ("Email",     "envelope.fill"),
        ("iMessage",  "message.fill"),
        ("WhatsApp",  "paperplane.fill"),
        ("X · Twitter", "square.and.arrow.up"),
        ("Facebook",  "person.2.fill"),
        ("Instagram", "camera.fill"),
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                foundersCard
                feedbackForm
                shareCard
                Text("THANK YOU · NEMARA v0.1")
                    .font(NemaraFont.eyebrow)
                    .tracking(0.5)
                    .foregroundStyle(NemaraColor.ink3)
                    .padding(.top, 4)
                    .padding(.bottom, 16)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(NemaraColor.paper)
        .navigationTitle("Feedback")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(NemaraColor.ink)
                }
            }
        }
    }

    private var foundersCard: some View {
        NemaraCard(tone: .terra, padding: 16, borderColor: .clear) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    NemaraMark(size: 42)
                    VStack(alignment: .leading, spacing: 4) {
                        NemaraEyebrow("FROM THE FOUNDERS", color: NemaraColor.terra)
                        Text("We read every message.")
                            .font(NemaraFont.title3)
                            .kerning(-0.3)
                            .foregroundStyle(NemaraColor.ink)
                    }
                    Spacer()
                }
                Text("Nemara is early, and your patient's story shapes what we build next. Tell us what landed, what didn't, what you wish it did.")
                    .font(NemaraFont.bodySmall)
                    .foregroundStyle(NemaraColor.ink2)
                    .lineSpacing(5)
                NemaraButton("Email the Nemara team", variant: .terra, size: .sm, block: true, systemImage: "envelope.fill") {}
                    .padding(.top, 4)
            }
        }
    }

    private var feedbackForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            NemaraEyebrow("FEEDBACK")
            NemaraCard(padding: 14) {
                VStack(alignment: .leading, spacing: 16) {
                    satisfactionScale
                    workingField
                    frustratingField
                    categorySection
                    includeContextRow
                    NemaraButton("Send feedback", variant: .primary, size: .lg, block: true, systemImage: "paperplane.fill") {}
                        .padding(.top, 6)
                }
            }
        }
    }

    private var satisfactionScale: some View {
        VStack(alignment: .leading, spacing: 6) {
            NemaraEyebrow("HOW IS NEMARA GOING FOR YOU?")
            let palette: [Color] = [
                Color(red: 0xA0/255, green: 0x43/255, blue: 0x31/255),
                Color(red: 0xC2/255, green: 0x62/255, blue: 0x44/255),
                Color(red: 0xC6/255, green: 0x8A/255, blue: 0x3D/255),
                Color(red: 0x8A/255, green: 0x8E/255, blue: 0x3A/255),
                Color(red: 0x4A/255, green: 0x5D/255, blue: 0x3A/255),
            ]
            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { n in
                    Button { rating = n } label: {
                        Text("\(n)")
                            .font(NemaraFont.bodySmallStrong)
                            .foregroundStyle(n <= rating ? NemaraColor.terraInk : NemaraColor.ink3)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(n <= rating ? palette[n - 1] : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.sm, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(NemaraColor.paperDim)
            .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous))
            HStack {
                Text("NOT GREAT").font(NemaraFont.monoSmall).foregroundStyle(NemaraColor.ink3)
                Spacer()
                Text("LOVE IT").font(NemaraFont.monoSmall).foregroundStyle(NemaraColor.ink3)
            }
        }
    }

    private var workingField: some View {
        VStack(alignment: .leading, spacing: 6) {
            NemaraEyebrow("WHAT'S WORKING?")
            ZStack(alignment: .topLeading) {
                if whatsWorking.isEmpty {
                    Text("What's landing well for you…")
                        .font(NemaraFont.bodySmall)
                        .foregroundStyle(NemaraColor.ink3)
                        .padding(12)
                }
                TextEditor(text: $whatsWorking)
                    .font(NemaraFont.bodySmall)
                    .foregroundStyle(NemaraColor.ink)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .tint(NemaraColor.terra)
            }
            .frame(minHeight: 64)
            .background(NemaraColor.paperDim)
            .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous))
        }
    }

    private var frustratingField: some View {
        VStack(alignment: .leading, spacing: 6) {
            NemaraEyebrow("WHAT'S FRUSTRATING?")
            ZStack(alignment: .topLeading) {
                if whatsFrustrating.isEmpty {
                    Text("Where Nemara fell short for you…")
                        .font(NemaraFont.bodySmall)
                        .foregroundStyle(NemaraColor.ink3)
                        .padding(12)
                }
                TextEditor(text: $whatsFrustrating)
                    .font(NemaraFont.bodySmall)
                    .foregroundStyle(NemaraColor.ink)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .tint(NemaraColor.terra)
            }
            .frame(minHeight: 64)
            .background(NemaraColor.paperDim)
            .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous))
        }
    }

    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                NemaraEyebrow("WHAT'S THIS ABOUT?")
                Text("optional")
                    .font(NemaraFont.caption.italic())
                    .foregroundStyle(NemaraColor.ink3)
            }
            FlexibleGrid(spacing: 6) {
                ForEach(categories, id: \.self) { name in
                    let on = category == name
                    Button { category = on ? nil : name } label: {
                        Text(name)
                            .font(NemaraFont.bodyMedium)
                            .foregroundStyle(on ? NemaraColor.terraInk : NemaraColor.ink2)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(on ? NemaraColor.terra : .clear)
                            .overlay(
                                Capsule().strokeBorder(on ? NemaraColor.terra : NemaraColor.line, lineWidth: 1)
                            )
                            .clipShape(Capsule(style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var includeContextRow: some View {
        HStack(spacing: 8) {
            Button { includeContext.toggle() } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(includeContext ? NemaraColor.action : .clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(includeContext ? .clear : NemaraColor.line, lineWidth: 1.5)
                        )
                        .frame(width: 18, height: 18)
                    if includeContext {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(NemaraColor.actionInk)
                    }
                }
            }
            .buttonStyle(.plain)
            VStack(alignment: .leading, spacing: 2) {
                Text("Include the last 24h of context")
                    .font(NemaraFont.bodySmallStrong.weight(.medium))
                    .foregroundStyle(NemaraColor.ink)
                Text("Recent events, device state, what page you were on.")
                    .font(NemaraFont.caption)
                    .foregroundStyle(NemaraColor.ink3)
            }
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(NemaraColor.paperDim)
        .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous))
    }

    private var shareCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            NemaraEyebrow("SHARE NEMARA")
            NemaraCard(padding: 14) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("If Nemara's made caring a little easier, pass it on.")
                        .font(NemaraFont.bodySmall)
                        .foregroundStyle(NemaraColor.ink2)
                        .lineSpacing(3)
                    HStack(spacing: 8) {
                        Image(systemName: "square.and.arrow.up")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(NemaraColor.ink3)
                        Text("nemara.app/join/jane-x84n")
                            .font(NemaraFont.mono(size: 12, weight: .semibold))
                            .foregroundStyle(NemaraColor.ink2)
                        Spacer()
                        Text("COPY")
                            .font(NemaraFont.mono(size: 10, weight: .bold))
                            .tracking(0.4)
                            .foregroundStyle(NemaraColor.terra)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(NemaraColor.paperDim)
                    .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous))

                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8),
                        GridItem(.flexible(), spacing: 8),
                    ], spacing: 8) {
                        ForEach(socials, id: \.label) { social in
                            VStack(spacing: 6) {
                                ZStack {
                                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                                        .fill(NemaraColor.paperDim)
                                    Image(systemName: social.icon)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(NemaraColor.ink2)
                                }
                                .frame(width: 36, height: 36)
                                Text(social.label)
                                    .font(NemaraFont.captionStrong)
                                    .foregroundStyle(NemaraColor.ink)
                            }
                            .padding(.vertical, 12)
                            .frame(maxWidth: .infinity)
                            .background(NemaraColor.paper)
                            .overlay(
                                RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous)
                                    .strokeBorder(NemaraColor.line, lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous))
                        }
                    }
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack { FeedbackView() }
        .environment(AppEnvironment.preview())
}
#endif
