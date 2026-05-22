import SwiftUI

/// "Add a detector" — prompt-first creation flow. The caregiver writes
/// what to watch for in natural language; Nemara (eventually) tunes the
/// model. For now Submit just appends a stub detector to the store.
struct AddDetectorView: View {
    let patientId: UUID
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var prompt = "Tell me if Maggie hasn't moved in the living room for more than 2 hours during the day."
    @State private var category: Detector.Category = .safety
    @State private var sensitivity: Detector.Sensitivity = .standard

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        intro
                        promptInput
                        eventTypeSelector
                        sensitivityPicker
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
                footer
            }
            .background(NemaraColor.paper)
        }
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
            Text("New detector")
                .font(NemaraFont.bodyLarge.weight(.semibold))
                .foregroundStyle(NemaraColor.ink)
            Spacer()
            Image(systemName: "xmark").opacity(0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .overlay(NemaraColor.line.frame(height: 1), alignment: .bottom)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            NemaraEyebrow("CUSTOM DETECTION", color: NemaraColor.terra)
            Text("What should Nemara watch for?")
                .font(NemaraFont.title1)
                .kerning(-0.7)
                .foregroundStyle(NemaraColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Describe it in your own words — what to look for, where, and when. Nemara will tune the detector to their baseline.")
                .font(NemaraFont.bodySmall)
                .foregroundStyle(NemaraColor.ink2)
                .lineSpacing(2)
        }
    }

    private var promptInput: some View {
        ZStack(alignment: .topLeading) {
            if prompt.isEmpty {
                Text("E.g. tell me when someone's at the front door after 9pm…")
                    .font(NemaraFont.body)
                    .foregroundStyle(NemaraColor.ink3)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)
            }
            TextEditor(text: $prompt)
                .font(NemaraFont.body)
                .foregroundStyle(NemaraColor.ink)
                .scrollContentBackground(.hidden)
                .padding(8)
                .tint(NemaraColor.terra)
        }
        .frame(minHeight: 92)
        .background(NemaraColor.card)
        .overlay(
            RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous)
                .strokeBorder(NemaraColor.ink, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous))
    }

    private var eventTypeSelector: some View {
        VStack(alignment: .leading, spacing: 8) {
            NemaraEyebrow("EVENT TYPE")
            HStack(spacing: 8) {
                typeCard(.safety, label: "Safety", sub: "Alarming · breaks through",
                         tone: NemaraColor.terra, soft: NemaraColor.terraSoft)
                typeCard(.routine, label: "Routine", sub: "Informational · daily log",
                         tone: NemaraColor.sky, soft: NemaraColor.skySoft)
            }
        }
    }

    private func typeCard(
        _ kind: Detector.Category,
        label: String,
        sub: String,
        tone: Color,
        soft: Color
    ) -> some View {
        let on = category == kind
        return Button { category = kind } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(tone)
                        .frame(width: 8, height: 8)
                    Text(label)
                        .font(NemaraFont.bodySmallStrong)
                        .foregroundStyle(on ? tone : NemaraColor.ink)
                }
                Text(sub)
                    .font(NemaraFont.caption)
                    .foregroundStyle(NemaraColor.ink3)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(on ? soft : NemaraColor.card)
            .overlay(
                RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous)
                    .strokeBorder(on ? tone : NemaraColor.line, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var sensitivityPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            NemaraEyebrow("SENSITIVITY")
            HStack(spacing: 6) {
                ForEach([Detector.Sensitivity.low, .standard, .high], id: \.self) { lvl in
                    let on = sensitivity == lvl
                    Button { sensitivity = lvl } label: {
                        Text(lvl.displayName)
                            .font(NemaraFont.bodySmallStrong)
                            .foregroundStyle(on ? NemaraColor.ink : NemaraColor.ink3)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(on ? NemaraColor.card : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.sm, style: .continuous))
                            .shadow(color: on ? NemaraColor.ink.opacity(0.06) : .clear, radius: 1, y: 1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(NemaraColor.paperDim)
            .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous))
            Text("You can tune this later from the detector's settings.")
                .font(NemaraFont.caption)
                .foregroundStyle(NemaraColor.ink3)
                .lineSpacing(2)
        }
    }

    private var footer: some View {
        NemaraButton("Create detector", variant: .primary, size: .lg, block: true) {
            create()
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(NemaraColor.paper)
        .overlay(NemaraColor.line.frame(height: 1), alignment: .top)
    }

    private func create() {
        let body = CreateDetectorRequest(
            name: derivedName(),
            iconName: category == .safety ? "exclamationmark.triangle" : "leaf",
            description: prompt,
            category: category,
            shape: .pointInTime,
            whereScope: "ALL ROOMS",
            whenScope: "CUSTOM",
            customPrompt: prompt,
            sensitivity: sensitivity,
        )
        Task {
            _ = try? await env.api.createCustomDetector(forPatient: patientId, body)
            dismiss()
        }
    }

    private func derivedName() -> String {
        let words = prompt.split(separator: " ").prefix(4).joined(separator: " ")
        return words.isEmpty ? "Custom detector" : String(words)
    }
}

#Preview {
    let env = AppEnvironment.preview()
    return AddDetectorView(patientId: env.api.patients[0].id)
        .environment(env)
}
