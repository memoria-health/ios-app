import SwiftUI

/// Step 2 of 2. Caregiver marks the event correct / not correct / unsure
/// and can leave free-text notes. Submit PATCHes the event row through
/// `NemaraAPIClient` — the backend stamps `reviewed_at = now()` when
/// `reviewed` flips false → true.
struct EventReviewView: View {
    let event: DetectionEvent
    let patientId: UUID
    /// Called by the events list to dismiss the whole modal stack
    /// after submit (so the caregiver lands back on the events page,
    /// not on the EventDetailView 1/2 they came from). Nil = use the
    /// local `dismiss()` (preview / standalone usage only).
    var onSubmitted: (() -> Void)? = nil
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var choice: DetectionEvent.ReviewChoice = .correct
    @State private var notes: String = ""

    private var subjectQuestion: String {
        switch event.category {
        case .safety:  "Was this a real \(event.title.lowercased())?"
        case .routine: "Was this the right thing to flag?"
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    intro

                    VStack(spacing: 8) {
                        choiceRow(.correct, label: "Correct", sub: subText(.correct), tone: NemaraColor.action, soft: NemaraColor.actionSoft, icon: "checkmark")
                        choiceRow(.wrong,   label: "Not correct", sub: subText(.wrong),   tone: NemaraColor.terra, soft: NemaraColor.terraSoft, icon: "xmark")
                        choiceRow(.unsure,  label: "Not sure",    sub: subText(.unsure),  tone: NemaraColor.ink2,  soft: NemaraColor.paperDim,  icon: "ellipsis")
                    }

                    notesField
                }
                .padding(.horizontal, 16)
                .padding(.top, 6)
                .padding(.bottom, 80)
            }
            .scrollDismissesKeyboard(.interactively)

            footer
        }
        .background(NemaraColor.paper)
        .navigationTitle("Review event")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text("2 / 2")
                    .font(NemaraFont.mono(size: 10, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(NemaraColor.ink3)
            }
        }
        .dismissKeyboardOnTap()
    }

    // MARK: - sections

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            NemaraEyebrow("YOUR REVIEW HELPS MEMORIA LEARN", color: NemaraColor.terra)
            Text(subjectQuestion)
                .font(NemaraFont.title1)
                .kerning(-0.7)
                .foregroundStyle(NemaraColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Your answer is private to this profile and tunes their detectors over time.")
                .font(NemaraFont.bodySmall)
                .foregroundStyle(NemaraColor.ink2)
                .lineSpacing(2)
        }
    }

    private func choiceRow(
        _ key: DetectionEvent.ReviewChoice,
        label: String,
        sub: String,
        tone: Color,
        soft: Color,
        icon: String
    ) -> some View {
        let on = choice == key
        return Button { choice = key } label: {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(on ? tone : NemaraColor.paperDim)
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(on ? NemaraColor.terraInk : NemaraColor.ink3)
                }
                .frame(width: 32, height: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).font(NemaraFont.bodySemibold).foregroundStyle(on ? tone : NemaraColor.ink)
                    Text(sub).font(NemaraFont.caption).foregroundStyle(NemaraColor.ink3)
                }
                Spacer()
                ZStack {
                    Circle().fill(on ? tone : .clear)
                    Circle().strokeBorder(on ? tone : NemaraColor.line, lineWidth: 1.5)
                    if on {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(NemaraColor.terraInk)
                    }
                }
                .frame(width: 20, height: 20)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(on ? soft : NemaraColor.card)
            .overlay(
                RoundedRectangle(cornerRadius: NemaraRadius.lg, style: .continuous)
                    .strokeBorder(on ? tone : NemaraColor.line, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                NemaraEyebrow("ANYTHING TO ADD?")
                Text("optional")
                    .font(NemaraFont.caption.italic())
                    .foregroundStyle(NemaraColor.ink3)
            }
            ZStack(alignment: .topLeading) {
                if notes.isEmpty {
                    Text("E.g. she tripped on the rug between the couch and coffee table…")
                        .font(NemaraFont.bodySmall)
                        .foregroundStyle(NemaraColor.ink3)
                        .padding(12)
                }
                TextEditor(text: $notes)
                    .font(NemaraFont.bodySmall)
                    .foregroundStyle(NemaraColor.ink)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .tint(NemaraColor.terra)
            }
            .frame(minHeight: 80)
            .background(NemaraColor.paperDim)
            .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous))
        }
    }

    private var footer: some View {
        NemaraButton("Submit review", variant: .primary, size: .lg, block: true) {
            submit()
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(NemaraColor.paper)
        .overlay(NemaraColor.line.frame(height: 1), alignment: .top)
    }

    /// Optimistic submit: write the reviewed state into the local
    /// observable cache and dismiss immediately, then fire the PATCH
    /// in a background Task. On failure we roll the cache back to the
    /// snapshot and publish the error on `env.api.lastReviewError` so
    /// the events view can show a dismissible banner. iOS gives the
    /// caregiver a snappy modal close without hiding network failures.
    private func submit() {
        let trimmedNotes = notes.isEmpty ? nil : notes
        let original = event
        let nowChoice = choice

        if var arr = env.api.eventsByPatient[patientId],
           let idx = arr.firstIndex(where: { $0.id == original.id }) {
            arr[idx].opened = true
            arr[idx].reviewed = true
            arr[idx].reviewChoice = nowChoice
            arr[idx].reviewNotes = trimmedNotes
            arr[idx].reviewedAt = Date()
            env.api.eventsByPatient[patientId] = arr
        }

        if let onSubmitted {
            onSubmitted()
        } else {
            dismiss()
        }

        Task {
            do {
                _ = try await env.api.updateEvent(
                    original.id,
                    UpdateEventRequest(
                        opened: true,
                        reviewed: true,
                        reviewChoice: nowChoice,
                        reviewNotes: trimmedNotes,
                    ),
                )
            } catch {
                if var arr = env.api.eventsByPatient[patientId],
                   let idx = arr.firstIndex(where: { $0.id == original.id }) {
                    arr[idx] = original
                    env.api.eventsByPatient[patientId] = arr
                }
                env.api.lastReviewError = "Couldn't save your review. \(error.localizedDescription) Tap the event to try again."
            }
        }
    }

    private func subText(_ k: DetectionEvent.ReviewChoice) -> String {
        switch (event.category, k) {
        case (.safety, .correct):  return "Yes, that was a real \(event.title.lowercased())."
        case (.safety, .wrong):    return "It wasn't a \(event.title.lowercased())."
        case (.routine, .correct): return "Yes, that's the right thing to flag."
        case (.routine, .wrong):   return "We shouldn't have flagged this."
        case (_, .unsure):         return "Hard to tell from the clip."
        }
    }
}

#if DEBUG
#Preview {
    let env = AppEnvironment.preview()
    let pid = env.api.patients[0].id
    return NavigationStack {
        EventReviewView(event: env.api.eventsByPatient[pid]![0], patientId: pid)
    }
    .environment(env)
}
#endif
