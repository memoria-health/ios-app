import SwiftUI

/// Set up a sensor that is on the account but not yet watching anyone.
///
/// The installer provisions sensors against the account; this is where the
/// caregiver names one, gives it an icon, and says who it watches. It can
/// cover more than one person — a shared lounge is one sensor, not one per
/// resident — and everyone it covers is an equal: there is no primary, and
/// picking nobody at all is a valid save. Coverage is attribution only, so
/// the sensor streams either way.
///
/// Nothing here is network discovery: the list comes from the backend, so
/// the caregiver can be anywhere when they set a sensor up.
struct AssignSensorSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var showingSetupCode = false
    @State private var cameras: [AccountCamera] = []
    @State private var loading = true
    @State private var loadError: String?

    @State private var selected: AccountCamera?
    @State private var name = ""
    @State private var icon = "tv"
    @State private var watchers: [UUID] = []
    @State private var saving = false
    @State private var saveError: String?
    @State private var saveTask: Task<Void, Never>?

    private static let icons = ["tv", "bed.double", "fork.knife", "sofa", "door.left.hand.open"]

    var body: some View {
        NavigationStack {
            picker
            .navigationTitle("Sensors")
            .navigationBarTitleDisplayMode(.inline)
            // A real push, so the system supplies the back chevron. The
            // hand-rolled "Back" button existed only because this was a
            // Group swapping on `selected`, and it sat next to "Save" in
            // a form section looking like a form control.
            .navigationDestination(item: $selected) { cam in
                configure(cam)
                    .navigationTitle(cam.room.isEmpty ? "Set up sensor" : cam.room)
                    .navigationBarTitleDisplayMode(.inline)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
                // Reachable from the EMPTY state too: the first sensor a
                // caregiver ever adds is added when the list is empty,
                // which is exactly when a button hidden behind a row
                // would not exist.
                if selected == nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button { showingSetupCode = true } label: {
                            Label("Add a sensor", systemImage: "plus")
                        }
                    }
                }
            }
        }
        .task { await load() }
        .sheet(isPresented: $showingSetupCode, onDismiss: {
            // The installer may have redeemed it while the sheet was up.
            Task { await load() }
        }) {
            // The SAME sheet the patient Live view opens. There is one
            // "add a sensor" screen, not one per entry point.
            AddCameraSheet(patientId: nil)
                .environment(env)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Pick a sensor
    //
    // ScrollView + NemaraCard, not List/Section. The system's inset-grouped
    // chrome brings its own greys, separators, corner radii and header
    // casing, none of which are ours, so this one screen looked like a
    // different app sitting behind sheets that are all hand-styled.

    private var picker: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if loading {
                    HStack(spacing: 10) {
                        ProgressView().tint(NemaraColor.ink3)
                        Text("Looking for sensors…")
                            .font(NemaraFont.bodySmall)
                            .foregroundStyle(NemaraColor.ink2)
                    }
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 40)
                } else if let loadError {
                    NemaraCard {
                        Text(loadError)
                            .font(NemaraFont.bodySmall)
                            .foregroundStyle(NemaraColor.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }

                if !loading {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("READY TO SET UP").nemaraEyebrow()
                        if unassigned.isEmpty {
                            NemaraCard {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("No sensors waiting to be set up.")
                                        .font(NemaraFont.body)
                                        .foregroundStyle(NemaraColor.ink2)
                                    Text("A sensor appears here once it has been installed for your account. Tap + for the code your installer needs.")
                                        .font(NemaraFont.caption)
                                        .foregroundStyle(NemaraColor.ink3)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                                // A card wraps its content, so without this
                                // it shrank to the longest line instead of
                                // filling the column like the sensor rows.
                                .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else {
                            VStack(spacing: 8) {
                                ForEach(unassigned) { cam in
                                    sensorRow(
                                        cam,
                                        subtitle: cam.online ? "Connected" : "Waiting for signal",
                                    ) {
                                        selected = cam
                                        name = cam.room
                                        icon = cam.iconName
                                        watchers = []
                                    }
                                }
                            }
                        }
                    }
                }

                if !assigned.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ALREADY SET UP").nemaraEyebrow()
                        VStack(spacing: 8) {
                            // `watchers` seeds from the sensor's CURRENT
                            // coverage, not emptied: opening one and leaving
                            // without touching anything must be a no-op.
                            ForEach(assigned) { cam in
                                sensorRow(cam, subtitle: watcherNames(cam)) {
                                    selected = cam
                                    name = cam.room
                                    icon = cam.iconName
                                    watchers = cam.patientIds
                                }
                            }
                        }
                        Text("Tap a sensor to rename it or change who it watches.")
                            .font(NemaraFont.caption)
                            .foregroundStyle(NemaraColor.ink3)
                            .padding(.horizontal, 4)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, NemaraSheetHandle.contentGap)
            .padding(.bottom, 24)
        }
        .background(NemaraColor.paper)
    }

    /// One sensor. Identical for assigned and unassigned so the two lists
    /// cannot drift; only the subtitle differs.
    private func sensorRow(
        _ cam: AccountCamera, subtitle: String, action: @escaping () -> Void,
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: cam.iconName)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(NemaraColor.ink2)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(cam.room)
                        .font(NemaraFont.body)
                        .foregroundStyle(NemaraColor.ink)
                    Text(subtitle)
                        .font(NemaraFont.caption)
                        .foregroundStyle(NemaraColor.ink3)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(NemaraColor.ink4)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: NemaraRadius.md)
                    .fill(NemaraColor.card)
            )
            .overlay(
                RoundedRectangle(cornerRadius: NemaraRadius.md)
                    .strokeBorder(NemaraColor.line, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Name it and say who it watches
    //
    // No Save, no Back. Every control writes immediately: a toggle or an
    // icon saves on tap, the name saves shortly after typing stops and
    // again on the way out. "Save" made a two-field screen feel like a
    // form you could get wrong, and it sat beside "Back" in a section,
    // which is why both looked like stray form rows rather than chrome.
    private func configure(_ cam: AccountCamera) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                NemaraCard {
                    VStack(alignment: .leading, spacing: 14) {
                        NemaraField("Name", text: $name, placeholder: "Living room")
                            .onChange(of: name) { scheduleSave(cam) }

                        Text("ICON").nemaraEyebrow()
                        HStack(spacing: 10) {
                            ForEach(Self.icons, id: \.self) { symbol in
                                Button {
                                    icon = symbol
                                    Task { await saveNow(cam) }
                                } label: {
                                    Image(systemName: symbol)
                                        .font(.system(size: 17, weight: .semibold))
                                        .foregroundStyle(icon == symbol
                                                         ? NemaraColor.actionInk : NemaraColor.ink2)
                                        .frame(width: 44, height: 40)
                                        .background(
                                            RoundedRectangle(cornerRadius: NemaraRadius.sm)
                                                .fill(icon == symbol
                                                      ? NemaraColor.action : NemaraColor.paperDim)
                                        )
                                        .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(symbol)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("WHO DOES THIS SENSOR WATCH?").nemaraEyebrow()
                    NemaraCard {
                        VStack(spacing: 0) {
                            ForEach(Array(env.api.patients.enumerated()), id: \.element.id) { idx, p in
                                if idx > 0 {
                                    Rectangle().fill(NemaraColor.line)
                                        .frame(height: 1).padding(.vertical, 4)
                                }
                                // A real toggle, and the WHOLE row flips it.
                                // This was a plain-styled Button wrapping an
                                // HStack with a Spacer and no contentShape, so
                                // only the name glyphs were hit-testable —
                                // most of the row, including all the empty
                                // space, silently ignored taps. That is why
                                // Margaret could not be selected.
                                Button {
                                    toggleWatcher(p.id, cam)
                                } label: {
                                    HStack {
                                        Text(p.preferredName)
                                            .font(NemaraFont.body)
                                            .foregroundStyle(NemaraColor.ink)
                                        Spacer()
                                        NemaraToggle(
                                            isOn: Binding(
                                                get: { watchers.contains(p.id) },
                                                set: { _ in toggleWatcher(p.id, cam) }
                                            ),
                                            track: "sensor.coverage",
                                        )
                                        .allowsHitTesting(false)
                                    }
                                    .padding(.vertical, 8)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    Text(watchers.count > 1
                         ? "Shared sensors need face setup for each person before personal routines are recorded. Safety alerts work either way."
                         : "Pick everyone this sensor can see. You can leave this empty and come back to it — the sensor still runs.")
                        .font(NemaraFont.caption)
                        .foregroundStyle(NemaraColor.ink3)
                        .padding(.horizontal, 4)
                }

                if let saveError {
                    Text(saveError)
                        .font(NemaraFont.bodySmall)
                        .foregroundStyle(NemaraColor.danger)
                } else if saving {
                    Text("Saving…")
                        .font(NemaraFont.caption)
                        .foregroundStyle(NemaraColor.ink3)
                }
            }
            .padding(20)
        }
        .background(NemaraColor.paper)
        // Catches a name typed and left before the debounce fired.
        .onDisappear {
            saveTask?.cancel()
            Task { await saveNow(cam) }
        }
    }

    private func toggleWatcher(_ id: UUID, _ cam: AccountCamera) {
        if let i = watchers.firstIndex(of: id) {
            watchers.remove(at: i)
        } else {
            watchers.append(id)
        }
        Task { await saveNow(cam) }
    }

    /// Debounced so a name is not POSTed on every keystroke.
    private func scheduleSave(_ cam: AccountCamera) {
        saveTask?.cancel()
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            await saveNow(cam)
        }
    }

    // MARK: - Data

    private var unassigned: [AccountCamera] { cameras.filter(\.unassigned) }
    private var assigned: [AccountCamera] { cameras.filter { !$0.unassigned } }

    private func watcherNames(_ cam: AccountCamera) -> String {
        let names = cam.patientIds.compactMap { id in
            env.api.patients.first { $0.id == id }?.preferredName
        }
        // "Nobody yet" instead of a blank trailing label: covering no one
        // is a legal state now, so this row can genuinely have no names.
        return names.isEmpty ? "Nobody yet" : names.joined(separator: ", ")
    }

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            cameras = try await env.api.fetchAccountCameras()
            loadError = nil
        } catch {
            loadError = "Could not load sensors. Pull to try again."
        }
    }

    /// Writes the whole sensor — name, icon, coverage — every time.
    /// `assignCamera` replaces coverage wholesale, so a partial write is
    /// not a thing that exists; sending current state is always correct.
    ///
    /// Does NOT dismiss. It used to, because it was only ever reached by
    /// a Save button; auto-saving on every toggle, that would throw the
    /// caregiver out of the sheet mid-edit.
    private func saveNow(_ cam: AccountCamera) async {
        guard !name.isEmpty else { return }
        saving = true
        defer { saving = false }
        do {
            try await env.api.assignCamera(
                cam.id, room: name, iconName: icon, patientIds: watchers,
            )
            // Refresh everyone who could be affected — including patients
            // just REMOVED from coverage, whose camera list is now stale.
            let touched = Set(watchers).union(cam.patientIds)
            for pid in touched { try? await env.api.loadCameras(forPatient: pid) }
            cameras = (try? await env.api.fetchAccountCameras()) ?? cameras
            saveError = nil
        } catch {
            saveError = "Could not save this sensor. Try again."
        }
    }
}
