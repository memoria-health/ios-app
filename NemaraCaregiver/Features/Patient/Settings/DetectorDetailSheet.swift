import SwiftUI

/// What a detector actually does, in the caregiver's language — and a way to
/// change it in plain words. Reworked 2026-07-26 to read as one coherent
/// editor (mirrors the web DetectorEditor):
///   what you asked for  →  what Memoria looks for  →  refine  →  where it runs
///
/// The refine box is a *preview*: "Re-generate" dry-runs the change and shows
/// what the criteria would become (item E8); nothing persists until Save. A
/// freshly-created detector lands here OFF (create-as-draft, item C2) so the
/// caregiver reviews the compiled criteria and turns it on deliberately.
struct DetectorDetailSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    let patientId: UUID
    @State var detector: Detector

    @State private var feedback = ""
    /// Previewed criteria from "Re-generate" — staged, not saved. Nil when we
    /// are showing the live compiled criteria.
    @State private var previewCriteria: [String]?
    @State private var regenerating = false
    // ── Alert timing (the discrete picker) ─────────────────────────────
    @State private var alertTrigger: Detector.AlertTrigger = .leading
    @State private var durationSeconds: Int?
    @State private var timingInit = false
    @State private var saving = false
    @State private var rewriting = false
    @State private var error: String?

    // Multi-room scope (item E4). Initialised from the detector on first
    // appear; `Save` persists it.
    @State private var allRooms = true
    @State private var selectedRooms: Set<String> = []
    @State private var roomsInitialised = false

    private var isCustom: Bool { detector.source == .custom }
    private var compiling: Bool { detector.identifier == nil }
    private var shownCriteria: [String] { previewCriteria ?? detector.userCriteria ?? [] }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    if let error { errorBanner(error) }
                    if detector.showsAccuracyCaveat { AccuracyCaveatNotice() }
                    if !detector.isOn { draftBanner }
                    if isCustom { askedForCard }
                    criteriaCard
                    if let refinements = detector.refinements, !refinements.isEmpty {
                        refinementsCard(refinements)
                    }
                    if isCustom { changeBox }
                    howItAlerts
                    if isCustom {
                        roomsCard
                    } else {
                        Text("This is a built-in detector, tuned by Memoria. Custom detectors you create can be adjusted in your own words.")
                            .font(NemaraFont.caption)
                            .foregroundStyle(NemaraColor.ink3)
                    }
                    if isCustom { saveBar }
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
            .onAppear(perform: initRoomsIfNeeded)
            .task(id: compiling) { await pollWhileCompiling() }
        }
    }

    // MARK: - Header

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

    // MARK: - Draft banner (create-as-draft, item C2)

    private var draftBanner: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text("This detector is off")
                    .font(NemaraFont.bodySmallStrong)
                    .foregroundStyle(NemaraColor.ink)
                Text("Review what Memoria will look for, then turn it on.")
                    .font(NemaraFont.caption)
                    .foregroundStyle(NemaraColor.ink2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Button("Turn on") { setOn(true) }
                .font(NemaraFont.bodySmallStrong)
                .buttonStyle(.borderedProminent)
                .tint(NemaraColor.terra)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NemaraColor.warning.opacity(0.12),
                    in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - What you asked for (item E5)

    private var askedForCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            NemaraEyebrow("WHAT YOU ASKED FOR")
            Text(detector.customPrompt?.isEmpty == false
                 ? detector.customPrompt!
                 : "—")
                .font(NemaraFont.bodySmall)
                .foregroundStyle(NemaraColor.ink)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NemaraColor.cardAlt, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    // MARK: - What Memoria looks for (items E1, E9)

    private var criteriaCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                NemaraEyebrow("WHAT MEMORIA LOOKS FOR", color: NemaraColor.terra)
                Spacer()
                if previewCriteria != nil {
                    Text("PREVIEW · NOT SAVED")
                        .font(NemaraFont.mono(size: 8.5, weight: .bold))
                        .tracking(0.5)
                        .foregroundStyle(NemaraColor.ink2)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(NemaraColor.paperDim)
                        .clipShape(Capsule(style: .continuous))
                }
            }

            if regenerating || (rewriting) || (compiling && shownCriteria.isEmpty) {
                GeneratingCriteriaView(
                    label: regenerating ? "Re-reading your change…"
                        : rewriting ? "Applying your change…"
                        : "Writing the instructions…",
                )
            } else if !shownCriteria.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(shownCriteria, id: \.self) { line in
                        Text(line)
                            .font(NemaraFont.bodySmall)
                            .foregroundStyle(NemaraColor.ink)
                            .lineSpacing(2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            } else {
                // Compiled but no bulleted summary yet — a neutral note (don't
                // echo "what you asked for" above; that read as repetition).
                Text("Memoria is finalizing this detector's details — check back in a moment.")
                    .font(NemaraFont.bodySmall)
                    .italic()
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

    // MARK: - Ask for a change → Re-generate previews (item E8)

    private var changeBox: some View {
        VStack(alignment: .leading, spacing: 8) {
            NemaraEyebrow("ASK FOR A CHANGE")
            Text("Tell Memoria in your own words — e.g. \u{201C}don't count eating as choking\u{201D}. Preview it, then Save to apply.")
                .font(NemaraFont.caption)
                .foregroundStyle(NemaraColor.ink3)
                .fixedSize(horizontal: false, vertical: true)
            TextField("What should work differently?", text: $feedback, axis: .vertical)
                .lineLimit(2...4)
                .font(NemaraFont.bodySmall)
                .padding(10)
                .background(NemaraColor.card, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .onChange(of: feedback) { _, _ in
                    if previewCriteria != nil { previewCriteria = nil }
                }
            Button {
                regenerate()
            } label: {
                HStack {
                    if regenerating { ProgressView().controlSize(.small) }
                    Text(regenerating ? "Re-generating…" : "Re-generate")
                        .font(NemaraFont.bodySmallStrong)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.bordered)
            .tint(NemaraColor.ink2)
            .disabled(regenerating || feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    // MARK: - Where it runs — multi-room (item E4)

    private var roomsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            NemaraEyebrow("WHERE IT RUNS")
            let opts = roomOptions
            FlowChips {
                chip("All rooms", selected: allRooms) {
                    allRooms = true
                    selectedRooms = []
                }
                ForEach(opts, id: \.self) { room in
                    chip(room, selected: !allRooms && selectedRooms.contains(room)) {
                        toggleRoom(room)
                    }
                }
            }
            if opts.isEmpty {
                Text("No cameras yet — this runs everywhere once you pair one.")
                    .font(NemaraFont.caption)
                    .foregroundStyle(NemaraColor.ink3)
            }
        }
    }

    private func chip(_ label: String, selected: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(NemaraFont.bodySmall.weight(.medium))
                .foregroundStyle(selected ? NemaraColor.paper : NemaraColor.ink2)
                .padding(.horizontal, 12)
                .padding(.vertical, 7)
                .background(selected ? NemaraColor.terra : NemaraColor.paperDim,
                            in: Capsule(style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Save bar (the one state button, item E8)

    private var saveBar: some View {
        Button {
            save()
        } label: {
            HStack {
                if saving { ProgressView().controlSize(.small) }
                Text(saving ? "Saving…" : "Save")
                    .font(NemaraFont.bodySmallStrong)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(.borderedProminent)
        .tint(NemaraColor.terra)
        .disabled(saving || !isDirty || timingInvalid)
    }

    private var howItAlerts: some View {
        // How it alerts — the alert TIMING. A read-only line for the current
        // trigger, plus a discrete picker for sustained activities (choose the
        // edge: as it happens / when it's over / if it lasts too long).
        // Instant + absence detectors have no edge to choose.
        VStack(alignment: .leading, spacing: 8) {
            NemaraEyebrow("HOW IT ALERTS")
            (Text(alertTrigger.caregiverLabel + ". ")
             + Text(alertTrigger.caregiverSub))
                .font(NemaraFont.bodySmall)
                .foregroundColor(NemaraColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            if isCustom && detector.isSustained && alertTrigger != .absence {
                FlowChips {
                    ForEach(
                        [Detector.AlertTrigger.leading, .trailing, .duration],
                        id: \.self,
                    ) { t in
                        chip(t.caregiverShort, selected: alertTrigger == t) {
                            alertTrigger = t
                        }
                    }
                }
                if alertTrigger == .duration {
                    HStack(spacing: 8) {
                        Text("Alert once it's continued past")
                            .font(NemaraFont.bodySmall)
                            .foregroundStyle(NemaraColor.ink3)
                        TextField("min", text: Binding(
                            get: { durationSeconds.map { String($0 / 60) } ?? "" },
                            set: { s in
                                let m = Int(s.filter(\.isNumber))
                                durationSeconds = m.map { max(1, min(1440, $0)) * 60 }
                            },
                        ))
                        .keyboardType(.numberPad)
                        .frame(width: 44)
                        .padding(6)
                        .background(NemaraColor.card, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                        Text("minutes")
                            .font(NemaraFont.bodySmall)
                            .foregroundStyle(NemaraColor.ink3)
                    }
                    if durationSeconds == nil {
                        Text("Set a time so I know when it's gone on too long.")
                            .font(NemaraFont.caption)
                            .foregroundStyle(NemaraColor.warning)
                    }
                }
            }
        }
    }

    // MARK: - State + actions

    private var roomOptions: [String] {
        let cams = env.api.camerasByPatient[patientId] ?? []
        var seen = Set<String>()
        var out: [String] = []
        for c in cams where !c.room.isEmpty && !seen.contains(c.room) {
            seen.insert(c.room)
            out.append(c.room)
        }
        return out
    }

    private var isDirty: Bool {
        if !feedback.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return true }
        if previewCriteria != nil { return true }
        if timingChanged && !timingInvalid { return true }
        return roomsChanged
    }

    private var timingChanged: Bool {
        alertTrigger != detector.alertTrigger
            || durationSeconds != detector.durationSeconds
    }

    /// A duration trigger needs a time — never save it without one.
    private var timingInvalid: Bool {
        alertTrigger == .duration && durationSeconds == nil
    }

    private var roomsChanged: Bool {
        let (initAll, initSet) = initialRoomState(detector)
        if allRooms != initAll { return true }
        if !allRooms { return selectedRooms != initSet }
        return false
    }

    private func initialRoomState(_ d: Detector) -> (Bool, Set<String>) {
        if let wr = d.whereRooms, !wr.isEmpty {
            if wr.contains(where: {
                $0.trimmingCharacters(in: .whitespaces).uppercased() == "ALL ROOMS"
            }) { return (true, []) }
            return (false, Set(wr))
        }
        if d.whereScope.trimmingCharacters(in: .whitespaces).uppercased() == "ALL ROOMS" {
            return (true, [])
        }
        return (false, [d.whereScope])
    }

    private func initRoomsIfNeeded() {
        guard !roomsInitialised else { return }
        (allRooms, selectedRooms) = initialRoomState(detector)
        roomsInitialised = true
        if !timingInit {
            alertTrigger = detector.alertTrigger
            durationSeconds = detector.durationSeconds
            timingInit = true
        }
    }

    private func toggleRoom(_ room: String) {
        allRooms = false
        if selectedRooms.contains(room) {
            selectedRooms.remove(room)
        } else {
            selectedRooms.insert(room)
        }
        if selectedRooms.isEmpty { allRooms = true } // empty is meaningless
    }

    private func setOn(_ on: Bool) {
        Task {
            if let updated = try? await env.api.updateDetector(
                detector.id, UpdateDetectorRequest(isOn: on),
            ) {
                detector = updated
            }
        }
    }

    private func regenerate() {
        let text = feedback.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        regenerating = true
        error = nil
        Task {
            do {
                // Dry-run: returns the criteria this change WOULD produce,
                // without persisting anything.
                let previewed = try await env.api.refineDetector(
                    detector.id, feedback: text, preview: true,
                )
                previewCriteria = previewed.userCriteria ?? []
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription
                    ?? "Couldn't preview that — please try again."
            }
            regenerating = false
        }
    }

    private func save() {
        saving = true
        error = nil
        let text = feedback.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            do {
                // 1) Room re-scope + alert-timing (both go through PATCH; the
                //    timing edge change needs no recompile — the detection
                //    fragment is unchanged, only when it fires).
                var patch = UpdateDetectorRequest()
                var hasPatch = false
                if roomsChanged {
                    patch.whereRooms = allRooms ? ["ALL ROOMS"] : Array(selectedRooms)
                    hasPatch = true
                }
                if timingChanged && !timingInvalid {
                    patch.alertTrigger = alertTrigger
                    patch.durationSeconds = alertTrigger == .duration ? durationSeconds : nil
                    hasPatch = true
                }
                if hasPatch {
                    detector = try await env.api.updateDetector(detector.id, patch)
                }
                // 2) Commit a pending refinement (recompiles on the backend).
                if isCustom, !text.isEmpty {
                    detector = try await env.api.refineDetector(
                        detector.id, feedback: text, preview: false,
                    )
                    feedback = ""
                    previewCriteria = nil
                    saving = false
                    // The rewrite runs a few seconds server-side; poll so the
                    // fresh summary lands without the caregiver doing anything.
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
                    return
                }
                saving = false
            } catch {
                saving = false
                rewriting = false
                self.error = (error as? LocalizedError)?.errorDescription
                    ?? "Couldn't save that — please try again."
            }
        }
    }

    /// Fresh drafts land here while the backend is still compiling. Poll the
    /// list until the compile lands so the criteria appear on their own.
    private func pollWhileCompiling() async {
        guard compiling else { return }
        for _ in 0..<15 {
            try? await Task.sleep(for: .seconds(1.5))
            try? await env.api.loadDetectors(forPatient: patientId)
            if let fresh = env.api.detectorsByPatient[patientId]?
                .first(where: { $0.id == detector.id }) {
                detector = fresh
                if fresh.identifier != nil { return }
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

/// Shimmer skeleton + a pulsing sparkle while criteria are (re)generating —
/// the "AI is thinking" feel instead of a bare spinner (item E1).
private struct GeneratingCriteriaView: View {
    let label: String
    @State private var pulse = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(NemaraColor.terra)
                    .opacity(pulse ? 0.4 : 1)
                Text(label)
                    .font(NemaraFont.bodySmall)
                    .italic()
                    .foregroundStyle(NemaraColor.ink2)
            }
            ForEach(0..<3, id: \.self) { i in
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(NemaraColor.line)
                    .frame(height: 10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.trailing, [40, 130, 80][i])
                    .opacity(pulse ? 0.35 : 0.85)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }
}

/// Minimal wrapping chip layout (SwiftUI `Layout`) so the room chips flow to
/// the next line instead of clipping.
private struct FlowChips: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for sub in subviews {
            let size = sub.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            sub.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
