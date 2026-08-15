import SwiftUI

/// The Home tab. Lists every patient the caregiver looks after.
///
/// Empty state defers to `EmptyRosterView`. Tapping a row drills into
/// the patient bundle; tapping `+` opens the new-patient sheet.
struct RosterView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var showingNewPatient = false
    @State private var showingEditProfile = false

    var body: some View {
        Group {
            if env.api.patients.isEmpty {
                EmptyRosterView(showingNewPatient: $showingNewPatient)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        roster_largeTitle(sub: "\(greeting), \(firstName)", title: "Today") {
                            AnyView(
                                HStack(spacing: 12) {
                                    Button { showingNewPatient = true } label: {
                                        Image(systemName: "plus")
                                            .font(.system(size: 20, weight: .semibold))
                                            .foregroundStyle(NemaraColor.ink)
                                    }
                                    .buttonStyle(.plain)
                                    // Welcome-tour anchor for replays: with
                                    // patients present the empty-state button
                                    // doesn't exist, so "add a patient" points
                                    // here instead. (Only one of the two is
                                    // ever on screen.)
                                    .tutorialTarget(.addPatient)
                                    Button { showingEditProfile = true } label: {
                                        NemaraAvatar(letter: firstName, size: 28)
                                    }
                                    .buttonStyle(.plain)
                                }
                            )
                        }

                        // Roster is just the rows (2026-08-15): the verdict
                        // card + AI briefing moved out — per-patient insight
                        // lives on each patient's Home tab now.
                        VStack(spacing: 10) {
                            // triage order: whoever needs eyes floats to the top
                            ForEach(env.api.patients.sorted { a, b in
                                func rank(_ s: Patient.State) -> Int {
                                    switch s { case .critical: return 0; case .offline: return 1; case .calm: return 2 }
                                }
                                return rank(a.state) < rank(b.state)
                            }) { p in
                                Button { env.deepLink.openPatient(p.id) } label: {
                                    PatientRow(patient: p)
                                }
                                .buttonStyle(.plain)
                                // Welcome-tour spotlight marker — first
                                // row only; reports a frame, no behavior.
                                .tutorialTarget(p.id == env.api.patients.first?.id ? .patientCard : nil)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                }
                .background(NemaraColor.paper)
                // Pull-to-refresh escape hatch for when Realtime drops
                // a row change (e.g. a delete done directly in Studio).
                // Refetches the roster + every per-patient sub-collection
                // so a single drag-down restores full sync.
                .refreshable {
                    do {
                        try await env.api.refresh()
                    } catch {
                        #if DEBUG
                        print("[RosterView] refresh failed: \(error)")
                        #endif
                    }
                }
            }
        }
        .sheet(isPresented: $showingNewPatient) {
            NewPatientView()
                .trackScreen("new_patient")
        }
        .sheet(isPresented: $showingEditProfile) {
            EditProfileView()
                .environment(env)
                .trackScreen("edit_profile")
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var firstName: String {
        env.auth.currentCaregiver?.displayName.split(separator: " ").first.map(String.init) ?? "Jane"
    }

    private var greeting: String {
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        default:      return "Good evening"
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack { RosterView() }
        .environment(AppEnvironment.preview())
}
#endif
