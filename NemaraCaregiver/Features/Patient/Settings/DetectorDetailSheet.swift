import SwiftUI

/// What a detector actually does, in the caregiver's language — and a
/// way to change it in plain words (customs visibility, 2026-07-18).
///
/// Shows the backend-generated criteria summary ("Counts: …" /
/// "Doesn't count: …" / "Caution: …"), the change requests made so
/// far, and — for custom detectors — an "Ask for a change" box that
/// posts to `/detectors/{id}/refine`. The backend rewrites the real
/// instructions and regenerates the summary; this sheet polls briefly
/// so the fresh summary appears without the user doing anything.
struct DetectorDetailSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    let patientId: UUID
    @State var detector: Detector

    @State private var feedback = ""
    @State private var submitting = false
    @State private var rewriting = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if let error { errorBanner(error) }
                    criteriaCard
                    if let refinements = detector.refinements, !refinements.isEmpty {
                        refinementsCard(refinements)
                    }
                    if detector.source == .custom {
                        changeBox
                    } else {
                        Text("This is a built-in detector, tuned by Memoria. Custom detectors you create can be adjusted in your own words.")
                            .font(NemaraFont.caption)
                            .foregroundStyle(NemaraColor.ink3)
                    }
                }
                .padding(20)
            }
            .background(NemaraColor.paper)
            .navigationTitle(detector.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(NemaraColor.paperDim)
                Image(systemName: detector.iconName)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(NemaraColor.ink2)
            }
            .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 3) {
                Text(detector.description)
                    .font(NemaraFont.bodySmall)
                    .foregroundStyle(NemaraColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
                if detector.whenScope.uppercased() != "ALWAYS" {
                    Text("Active: \(detector.whenScope)")
                        .font(NemaraFont.caption)
                        .foregroundStyle(NemaraColor.ink3)
                }
            }
        }
    }

    private var criteriaCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            NemaraEyebrow("WHAT MEMORIA LOOKS FOR", color: NemaraColor.terra)
            if rewriting {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Rewriting the instructions…")
                        .font(NemaraFont.bodySmall)
                        .foregroundStyle(NemaraColor.ink2)
                }
            } else if let criteria = detector.userCriteria, !criteria.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(criteria, id: \.self) { line in
                        Text(line)
                            .font(NemaraFont.bodySmall)
                            .foregroundStyle(NemaraColor.ink)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                Text(detector.identifier == nil
                     ? "Memoria is writing this detector's instructions…"
                     : "A summary isn't available for this detector yet.")
                    .font(NemaraFont.bodySmall)
                    .foregroundStyle(NemaraColor.ink3)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NemaraColor.cardAlt, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func refinementsCard(_ refinements: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            NemaraEyebrow("CHANGES YOU'VE ASKED FOR")
            ForEach(Array(refinements.enumerated()), id: \.offset) { _, r in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text("•").foregroundStyle(NemaraColor.ink3)
                    Text(r)
                        .font(NemaraFont.caption)
                        .foregroundStyle(NemaraColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var changeBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            NemaraEyebrow("ASK FOR A CHANGE")
            Text("Tell Memoria in your own words — e.g. \u{201C}don't count eating as choking\u{201D}.")
                .font(NemaraFont.caption)
                .foregroundStyle(NemaraColor.ink3)
            TextField("What should work differently?", text: $feedback, axis: .vertical)
                .lineLimit(2...4)
                .font(NemaraFont.bodySmall)
                .padding(10)
                .background(NemaraColor.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            Button {
                submit()
            } label: {
                HStack {
                    if submitting { ProgressView().controlSize(.small) }
                    Text(submitting ? "Sending…" : "Update detector")
                        .font(NemaraFont.bodySmallStrong)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .tint(NemaraColor.terra)
            .disabled(submitting || feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func submit() {
        let text = feedback.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        submitting = true
        error = nil
        Task {
            do {
                let updated = try await env.api.refineDetector(detector.id, feedback: text)
                detector = updated
                feedback = ""
                submitting = false
                // The rewrite runs in the backend for a few seconds;
                // poll a couple of times so the fresh summary appears.
                rewriting = true
                for _ in 0..<3 {
                    try? await Task.sleep(for: .seconds(4))
                    try? await env.api.loadDetectors(forPatient: patientId)
                    if let fresh = env.api.detectorsByPatient[patientId]?
                        .first(where: { $0.id == detector.id }),
                       fresh.updatedAt > detector.updatedAt {
                        detector = fresh
                        break
                    }
                }
                rewriting = false
            } catch {
                submitting = false
                rewriting = false
                self.error = (error as? LocalizedError)?.errorDescription
                    ?? "Couldn't send that — please try again."
            }
        }
    }

    private func errorBanner(_ msg: String) -> some View {
        Text(msg)
            .font(NemaraFont.caption)
            .foregroundStyle(NemaraColor.terra)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NemaraColor.terraSoft)
            .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.sm, style: .continuous))
    }
}
