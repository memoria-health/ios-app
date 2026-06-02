import SwiftUI

/// Combined feedback / share / contact screen. Pushed from
/// PatientSettings's "Feedback & support" row. Self-contained — no
/// nested navigation.
struct FeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var env
    @State private var rating: Int = 0
    @State private var whatsWorking: String = ""
    @State private var whatsFrustrating: String = ""
    @State private var category: String?
    @State private var isSubmitting = false
    @State private var submitted = false
    @State private var submitError: String?

    // Macro themes, not per-tab/feature buckets — feature-specific items
    // read like bug reports. These capture how Memoria is landing overall.
    private let categories = ["Ease of use", "Accuracy & reliability", "Peace of mind", "Feature request", "Pricing", "Something else"]

    private var canSubmit: Bool {
        rating > 0
            || !whatsWorking.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !whatsFrustrating.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @MainActor
    private func submit() async {
        guard canSubmit, !isSubmitting else { return }
        isSubmitting = true
        submitError = nil
        defer { isSubmitting = false }
        func nonBlank(_ s: String) -> String? {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        do {
            _ = try await env.api.submitFeedback(
                rating: rating == 0 ? nil : rating,
                whatsWorking: nonBlank(whatsWorking),
                whatsFrustrating: nonBlank(whatsFrustrating),
                category: category,
            )
            submitted = true
        } catch {
            submitError = "Couldn't send feedback. \(error.localizedDescription)"
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                foundersCard
                feedbackForm
                Text("THANK YOU · MEMORIA v0.1")
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
        .scrollDismissesKeyboard(.interactively)
        .dismissKeyboardOnTap()
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
                Text("Memoria is early, and your patient's story shapes what we build next. Tell us what landed, what didn't, what you wish it did.")
                    .font(NemaraFont.bodySmall)
                    .foregroundStyle(NemaraColor.ink2)
                    .lineSpacing(5)
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
                    if submitted {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(NemaraColor.action)
                            Text("Thanks — we got it.")
                                .font(NemaraFont.bodySmallStrong)
                                .foregroundStyle(NemaraColor.ink)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 6)
                    } else {
                        if let submitError {
                            Text(submitError)
                                .font(NemaraFont.caption)
                                .foregroundStyle(NemaraColor.terra)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        NemaraButton(
                            isSubmitting ? "Sending…" : "Send feedback",
                            variant: .primary, size: .lg, block: true,
                            systemImage: "paperplane.fill",
                        ) {
                            Task { await submit() }
                        }
                        .disabled(isSubmitting || !canSubmit)
                        .opacity((isSubmitting || !canSubmit) ? 0.5 : 1)
                        .padding(.top, 6)
                    }
                }
            }
        }
    }

    private var satisfactionScale: some View {
        VStack(alignment: .leading, spacing: 6) {
            NemaraEyebrow("HOW IS MEMORIA GOING FOR YOU?")
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
                    Text("Where Memoria fell short for you…")
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

}

#if DEBUG
#Preview {
    NavigationStack { FeedbackView() }
        .environment(AppEnvironment.preview())
}
#endif
