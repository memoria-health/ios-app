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

    @State private var cameras: [AccountCamera] = []
    @State private var loading = true
    @State private var loadError: String?

    @State private var selected: AccountCamera?
    @State private var name = ""
    @State private var icon = "tv"
    @State private var watchers: [UUID] = []
    @State private var saving = false
    @State private var saveError: String?

    private static let icons = ["tv", "bed.double", "fork.knife", "sofa", "door.left.hand.open"]

    var body: some View {
        NavigationStack {
            Group {
                if let cam = selected {
                    configure(cam)
                } else {
                    picker
                }
            }
            .navigationTitle(selected == nil ? "Sensors" : "Set up sensor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task { await load() }
    }

    // MARK: - Pick a camera

    private var picker: some View {
        List {
            if loading {
                HStack { ProgressView(); Text("Looking for sensors…") }
            } else if let loadError {
                Text(loadError).foregroundStyle(NemaraColor.danger)
            } else if unassigned.isEmpty {
                Section {
                    Text("No sensors waiting to be set up.")
                        .foregroundStyle(NemaraColor.ink3)
                } footer: {
                    Text("A sensor appears here once it has been installed for your account.")
                }
            } else {
                Section("Ready to set up") {
                    ForEach(unassigned) { cam in
                        Button {
                            selected = cam
                            name = cam.room
                            icon = cam.iconName
                            watchers = []
                        } label: {
                            HStack {
                                Image(systemName: cam.iconName)
                                VStack(alignment: .leading) {
                                    Text(cam.room)
                                    Text(cam.online ? "Connected" : "Waiting for signal")
                                        .font(.caption)
                                        .foregroundStyle(NemaraColor.ink3)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(NemaraColor.ink3)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !assigned.isEmpty {
                Section("Already set up") {
                    ForEach(assigned) { cam in
                        HStack {
                            Image(systemName: cam.iconName)
                            Text(cam.room)
                            Spacer()
                            Text(watcherNames(cam))
                                .font(.caption)
                                .foregroundStyle(NemaraColor.ink3)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Name it and say who it watches

    private func configure(_ cam: AccountCamera) -> some View {
        Form {
            Section("Name") {
                TextField("Living room", text: $name)
            }
            Section("Icon") {
                Picker("Icon", selection: $icon) {
                    ForEach(Self.icons, id: \.self) { Image(systemName: $0).tag($0) }
                }
                .pickerStyle(.segmented)
            }
            Section {
                ForEach(env.api.patients, id: \.id) { p in
                    Button {
                        if let i = watchers.firstIndex(of: p.id) {
                            watchers.remove(at: i)
                        } else {
                            watchers.append(p.id)
                        }
                    } label: {
                        HStack {
                            Text(p.preferredName)
                            Spacer()
                            if watchers.contains(p.id) {
                                Image(systemName: "checkmark")
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            } header: {
                Text("Who does this sensor watch?")
            } footer: {
                Text(watchers.count > 1
                     ? "Shared sensors need face setup for each person before personal routines are recorded. Safety alerts work either way."
                     : "Pick everyone this sensor can see. You can leave this empty and come back to it — the sensor still runs.")
            }

            if let saveError {
                Text(saveError).foregroundStyle(NemaraColor.danger)
            }

            Section {
                // No `watchers.isEmpty` gate: an empty pick is now a real
                // choice ("watched by nobody yet"), and blocking Save on it
                // would leave the caregiver stuck on this screen with no way
                // to just name the sensor.
                Button(saving ? "Saving…" : "Save") { Task { await save(cam) } }
                    .disabled(name.isEmpty || saving)
                Button("Back") { selected = nil }
            }
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

    private func save(_ cam: AccountCamera) async {
        saving = true
        defer { saving = false }
        do {
            try await env.api.assignCamera(
                cam.id, room: name, iconName: icon, patientIds: watchers,
            )
            for pid in watchers { try? await env.api.loadCameras(forPatient: pid) }
            dismiss()
        } catch {
            saveError = "Could not save this sensor. Try again."
        }
    }
}
