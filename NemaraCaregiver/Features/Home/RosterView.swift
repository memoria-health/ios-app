import SwiftUI

/// The Home tab. Lists every patient the caregiver looks after.
///
/// Empty state defers to `EmptyRosterView`. Tapping a row drills into
/// the patient bundle; tapping `+` opens the new-patient sheet.
struct RosterView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var showingNewPatient = false
    @State private var openPatientId: UUID?

    var body: some View {
        Group {
            if env.mockStore.patients.isEmpty {
                EmptyRosterView(showingNewPatient: $showingNewPatient)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        roster_largeTitle(sub: "Good morning, \(firstName)", title: "Today") {
                            AnyView(
                                HStack(spacing: 12) {
                                    Button { showingNewPatient = true } label: {
                                        Image(systemName: "plus")
                                            .font(.system(size: 20, weight: .semibold))
                                            .foregroundStyle(NemaraColor.ink)
                                    }
                                    .buttonStyle(.plain)
                                    NemaraAvatar(letter: firstName, size: 28)
                                }
                            )
                        }

                        VStack(spacing: 10) {
                            ForEach(env.mockStore.patients) { p in
                                Button { openPatientId = p.id } label: {
                                    PatientRow(patient: p)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 16)
                    }
                }
                .background(NemaraColor.paper)
            }
        }
        .fullScreenCover(item: Binding(
            get: { openPatientId.map(IdentifiableUUID.init) },
            set: { openPatientId = $0?.id }
        )) { wrap in
            PatientShell(patientId: wrap.id)
                .environment(env)
        }
        .sheet(isPresented: $showingNewPatient) {
            NewPatientView()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .task {
            #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-openFirstPatient"),
               openPatientId == nil {
                openPatientId = env.mockStore.patients.first?.id
            }
            #endif
        }
    }

    private var firstName: String {
        env.auth.currentCaregiver?.displayName.split(separator: " ").first.map(String.init) ?? "Jane"
    }
}

/// Tiny wrapper to make `UUID` work with `.fullScreenCover(item:)`,
/// which requires `Identifiable`. Adding `Identifiable` to `UUID`
/// directly would conflict with potential standard-library
/// conformance, so we wrap.
private struct IdentifiableUUID: Identifiable, Hashable {
    let id: UUID
}

#Preview {
    NavigationStack { RosterView() }
        .environment({
            let env = AppEnvironment(auth: MockAuthService(), mockStore: MockStore())
            env.auth.currentCaregiver = Caregiver(id: UUID(), displayName: "Jane Patel", email: "jane@patel.co")
            return env
        }())
}
