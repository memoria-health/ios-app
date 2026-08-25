import SwiftUI

/// The detection-library picker — the prebuilt detectors for the patient's
/// cohort (child vs adult; the backend derives the cohort from the patient's
/// date of birth), with a search bar and multi-select.
///
/// Two modes:
///  - `.add` (Detectors tab): add newly-checked entries. Entries the patient
///    already has are shown disabled ("Added"). On confirm we POST only the
///    new keys to `from-library` and dismiss.
///  - `.onboarding` (right after a patient is created): the recommended /
///    auto-seeded set is pre-checked but uncheckable. On Continue we RECONCILE:
///    add newly-checked keys, delete unchecked-but-present ones — and only ever
///    touch catalog detectors (matched by identifier), never custom ones.
struct DetectorLibraryView: View {
    enum Mode { case add, onboarding }

    let patientId: UUID
    var mode: Mode = .add
    /// Onboarding only — advance to the next onboarding step. Ignored in `.add`.
    var onContinue: (() -> Void)? = nil

    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var entries: [DetectorLibraryEntry] = []
    @State private var selectedKeys: Set<String> = []
    @State private var query = ""
    @State private var isLoading = true
    @State private var loadError: String?
    // Wandering is per-camera: right after adding it, ask WHICH cameras
    // should watch for it (sets whereRooms; the exit-door section then only
    // appears on those cameras).
    @State private var wanderingRoomPrompt = false
    @State private var wanderingRooms: Set<String> = []
    @State private var isSubmitting = false
    @State private var submitError: String?

    var body: some View {
        VStack(spacing: 0) {
            header
            if isLoading {
                Spacer()
                ProgressView().tint(NemaraColor.terra)
                Spacer()
            } else if let loadError {
                Spacer()
                VStack(spacing: 8) {
                    Text("Couldn't load the detection library.")
                        .font(NemaraFont.bodySemibold)
                        .foregroundStyle(NemaraColor.ink)
                    Text(loadError)
                        .font(NemaraFont.caption)
                        .foregroundStyle(NemaraColor.ink3)
                        .multilineTextAlignment(.center)
                    NemaraButton("Retry", variant: .secondary) {
                        Task { await load() }
                    }
                }
                .padding(.horizontal, 32)
                Spacer()
            } else {
                searchBar
                listScroll
            }
            footer
        }
        .background(NemaraColor.paper)
        .task { await load() }
        .sheet(isPresented: $wanderingRoomPrompt) {
            WanderingRoomsSheet(
                rooms: Array(Set((env.api.camerasByPatient[patientId] ?? []).map(\.room).filter { !$0.isEmpty })).sorted(),
                selected: $wanderingRooms,
            ) {
                Task {
                    if let wd = (env.api.detectorsByPatient[patientId] ?? []).first(where: { $0.identifier == "wandering" }),
                       !wanderingRooms.isEmpty {
                        var patch = UpdateDetectorRequest()
                        patch.whereRooms = Array(wanderingRooms)
                        _ = try? await env.api.updateDetector(wd.id, patch)
                    }
                    wanderingRoomPrompt = false
                    dismiss()
                }
            }
        }
    }

    // MARK: - chrome

    private var header: some View {
        HStack {
            // Onboarding can skip the whole step; add-mode just closes.
            Button {
                if mode == .onboarding { onContinue?() } else { dismiss() }
            } label: {
                Text(mode == .onboarding ? "Skip" : "Cancel")
                    .font(NemaraFont.bodySmall)
                    .foregroundStyle(NemaraColor.ink3)
            }
            .buttonStyle(.plain)
            Spacer()
            Text("Detection library")
                .font(NemaraFont.bodyLarge.weight(.semibold))
                .foregroundStyle(NemaraColor.ink)
                .kerning(-0.2)
            Spacer()
            // Balance the leading button so the title stays centered.
            Text(mode == .onboarding ? "Skip" : "Cancel")
                .font(NemaraFont.bodySmall)
                .opacity(0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 14)
        .padding(.bottom, 12)
        .background(NemaraColor.paper)
        .overlay(NemaraColor.line.frame(height: 1), alignment: .bottom)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(NemaraColor.ink3)
            TextField("Search detectors", text: $query)
                .font(NemaraFont.bodyLarge)
                .foregroundStyle(NemaraColor.ink)
                .tint(NemaraColor.terra)
                .autocorrectionDisabled()
            if !query.isEmpty {
                Button { query = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(NemaraColor.ink3)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background(NemaraColor.card)
        .overlay(
            RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous)
                .strokeBorder(NemaraColor.line, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous))
        .padding(.horizontal, 16)
        .padding(.top, 14)
        .padding(.bottom, 6)
    }

    @ViewBuilder
    private var listScroll: some View {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let recommended = filtered(q).filter(\.recommended)
        let more = filtered(q).filter { !$0.recommended }
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // First-run intro — only at onboarding, where the user is brand
                // new and won't know this list exists elsewhere or that custom
                // detectors are a thing.
                if mode == .onboarding {
                    NemaraCard(tone: .terra, padding: 14, borderColor: .clear) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Add a few pre-built detections")
                                .font(NemaraFont.bodySemibold)
                                .foregroundStyle(NemaraColor.ink)
                            Text("Pick any of these to start. You can always come back here later — and you can also create your own custom detectors.")
                                .font(NemaraFont.bodySmall)
                                .foregroundStyle(NemaraColor.ink2)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .padding(.horizontal, 16)
                }
                if filtered(q).isEmpty {
                    Text("No detectors match “\(query)”.")
                        .font(NemaraFont.bodySmall)
                        .foregroundStyle(NemaraColor.ink3)
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                }
                if !recommended.isEmpty {
                    section(title: "RECOMMENDED", entries: recommended)
                }
                // The rest, segregated by category in the palette order
                // (Aryaman 2026-08-17) — one flat MORE DETECTORS pile made
                // safety and routine reads compete.
                ForEach(Detector.Category.selectable, id: \.self) { cat in
                    let rows = more.filter { $0.category == cat }
                    if !rows.isEmpty {
                        section(title: cat.displayName.uppercased(), entries: rows)
                    }
                }
                // Honest empty-camera note (matches the backend behaviour:
                // detectors start running when the first camera is paired).
                Text("These start watching as soon as you add a sensor.")
                    .font(NemaraFont.caption)
                    .foregroundStyle(NemaraColor.ink3)
                    .padding(.horizontal, 16)
                    .padding(.top, 4)
                    .padding(.bottom, 24)
            }
            .padding(.top, 8)
        }
    }

    private func section(title: String, entries rows: [DetectorLibraryEntry]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            NemaraEyebrow(title)
                .padding(.horizontal, 16)
            NemaraCard(padding: 0) {
                VStack(spacing: 0) {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { idx, e in
                        if idx > 0 {
                            NemaraColor.line.frame(height: 1).padding(.leading, 52)
                        }
                        row(e)
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func row(_ e: DetectorLibraryEntry) -> some View {
        // In add-mode, an already-added detector can't be re-added (locked).
        // In onboarding, already-added entries ARE toggleable (uncheck = remove),
        // but a `recommended` entry stays locked-on so the defaults can't be lost
        // by accident… actually we let recommended be unchecked too, per spec.
        let locked = (mode == .add && e.alreadyAdded)
        let selected = selectedKeys.contains(e.key)
        return Button {
            toggle(e)
        } label: {
            HStack(spacing: 12) {
                // Category accent, not a hardcoded hue — this row serves
                // BOTH the library page and the first-time onboarding
                // picker, and the icon colour must match the category
                // palette everywhere (Aryaman 2026-08-17).
                Image(systemName: e.iconName)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(e.category.accent)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(e.name)
                        .font(NemaraFont.bodySemibold)
                        .foregroundStyle(NemaraColor.ink)
                    Text(e.description)
                        .font(NemaraFont.caption)
                        .foregroundStyle(NemaraColor.ink3)
                        .lineSpacing(1)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                    if e.showsAccuracyCaveat {
                        AccuracyCaveatNotice(compact: true)
                            .padding(.top, 3)
                    }
                }
                Spacer(minLength: 8)
                trailing(locked: locked, selected: selected)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(locked)
    }

    @ViewBuilder
    private func trailing(locked: Bool, selected: Bool) -> some View {
        if locked {
            Text("ADDED")
                .font(NemaraFont.mono(size: 9, weight: .semibold))
                .tracking(0.5)
                .foregroundStyle(NemaraColor.ink3)
        } else {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 20))
                .foregroundStyle(selected ? NemaraColor.terra : NemaraColor.ink3)
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if let submitError {
                Text(submitError)
                    .font(NemaraFont.bodySmall)
                    .foregroundStyle(NemaraColor.terra)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            NemaraButton(
                footerTitle,
                variant: .primary, block: true,
            ) {
                Task { await submit() }
            }
            .disabled(isSubmitting || footerDisabled)
            .opacity((isSubmitting || footerDisabled) ? 0.5 : 1)
            // Welcome-tour marker (onboarding flow only): rings Continue
            // while leaving the detector toggles free. Frame only.
            .tutorialTarget(mode == .onboarding && !isSubmitting ? .enrollContinue : nil)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(NemaraColor.paper)
        .overlay(NemaraColor.line.frame(height: 1), alignment: .top)
    }

    private var newlySelectedCount: Int {
        // Keys selected that aren't already on the patient.
        let present = Set(entries.filter(\.alreadyAdded).map(\.key))
        return selectedKeys.subtracting(present).count
    }

    private var footerTitle: String {
        if isSubmitting { return "Saving…" }
        switch mode {
        case .add:
            return newlySelectedCount == 0
                ? "Add detectors"
                : "Add \(newlySelectedCount) detector\(newlySelectedCount == 1 ? "" : "s")"
        case .onboarding:
            return "Continue"
        }
    }

    private var footerDisabled: Bool {
        // Add-mode needs at least one new pick; onboarding's Continue is always
        // available (it may just be "no change + advance").
        mode == .add && newlySelectedCount == 0
    }

    // MARK: - data

    private func filtered(_ q: String) -> [DetectorLibraryEntry] {
        guard !q.isEmpty else { return entries }
        return entries.filter {
            $0.name.lowercased().contains(q) || $0.description.lowercased().contains(q)
        }
    }

    private func toggle(_ e: DetectorLibraryEntry) {
        if mode == .add && e.alreadyAdded { return }   // locked
        if selectedKeys.contains(e.key) {
            selectedKeys.remove(e.key)
        } else {
            selectedKeys.insert(e.key)
        }
    }

    private func load() async {
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            // Load the patient's current detectors first so the onboarding
            // reconcile can map identifier → detector id for deletes, and so the
            // local cache is fresh.
            try await env.api.loadDetectors(forPatient: patientId)
            let lib = try await env.api.fetchDetectorLibrary(forPatient: patientId)
            entries = lib
            if mode == .onboarding {
                // Pre-check the recommended / already-seeded set.
                selectedKeys = Set(
                    lib.filter { $0.recommended || $0.alreadyAdded }.map(\.key)
                )
            } else {
                selectedKeys = []
            }
        } catch {
            loadError = error.localizedDescription
        }
    }

    private func submit() async {
        isSubmitting = true
        submitError = nil
        defer { isSubmitting = false }
        do {
            switch mode {
            case .add:
                let present = Set(entries.filter(\.alreadyAdded).map(\.key))
                let toAdd = Array(selectedKeys.subtracting(present))
                if !toAdd.isEmpty {
                    _ = try await env.api.addDetectorsFromLibrary(forPatient: patientId, keys: toAdd)
                }
                if toAdd.contains("wandering") {
                    wanderingRoomPrompt = true   // sheet PATCHes rooms, then dismisses
                } else {
                    dismiss()
                }
            case .onboarding:
                let present = Set(entries.filter(\.alreadyAdded).map(\.key))
                let desired = selectedKeys
                let toAdd = Array(desired.subtracting(present))
                let toRemove = present.subtracting(desired)
                if !toAdd.isEmpty {
                    _ = try await env.api.addDetectorsFromLibrary(forPatient: patientId, keys: toAdd)
                }
                if !toRemove.isEmpty {
                    let dets = env.api.detectorsByPatient[patientId] ?? []
                    for key in toRemove {
                        guard let det = dets.first(where: { $0.identifier == key }) else {
                            // The library said this key is present but we can't
                            // find its row — surface it rather than silently
                            // skipping (fail loud).
                            throw DetectorLibraryError.missingDetectorForKey(key)
                        }
                        try await env.api.deleteDetector(det.id)
                    }
                }
                onContinue?()
            }
        } catch {
            submitError = error.localizedDescription
        }
    }
}

private struct WanderingRoomsSheet: View {
    let rooms: [String]
    @Binding var selected: Set<String>
    var onDone: () -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(rooms, id: \.self) { room in
                        Button {
                            if selected.contains(room) { selected.remove(room) } else { selected.insert(room) }
                        } label: {
                            HStack {
                                Text(room).foregroundStyle(NemaraColor.ink)
                                Spacer()
                                if selected.contains(room) {
                                    Image(systemName: "checkmark").foregroundStyle(NemaraColor.terra)
                                }
                            }
                        }
                    }
                } header: {
                    Text("Which sensors should watch for wandering?")
                } footer: {
                    Text("Exit-door setup will only appear on these sensors. Leave empty for all sensors.")
                }
            }
            .navigationTitle("Wandering sensors")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { onDone() } } }
        }
    }
}

private enum DetectorLibraryError: LocalizedError {
    case missingDetectorForKey(String)
    var errorDescription: String? {
        switch self {
        case .missingDetectorForKey(let key):
            return "Couldn't find the detector to remove for “\(key)”."
        }
    }
}
