import SwiftUI

/// Caregiver-level account settings. Surfaced on the Settings tab of the
/// app shell. Lists patients, notification toggles, account actions.
struct AppSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var showingEditProfile = false
    @State private var showingContactSupport = false
    @State private var showingPrivacy = false
    @State private var showingNewPatient = false
    @State private var openPatientId: UUID?
    // Account-deletion flow state.
    @State private var showDeleteConfirm = false
    @State private var isDeleting = false
    @State private var deleteError: String?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                roster_largeTitle(title: "Settings")

                caregiverCard
                Group {
                    NemaraEyebrow("YOUR PATIENTS").frame(maxWidth: .infinity, alignment: .leading)
                    patientsCard
                    NemaraButton("Add another patient", variant: .ghost, size: .sm, systemImage: "plus") {
                        showingNewPatient = true
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 16)

                Group {
                    NemaraEyebrow("ACCOUNT").frame(maxWidth: .infinity, alignment: .leading)
                    accountCard
                }
                .padding(.horizontal, 16)

                Text("NEMARA v0.1")
                    .font(NemaraFont.eyebrow)
                    .tracking(0.5)
                    .foregroundStyle(NemaraColor.ink3)
                    .padding(.top, 8)
                    .padding(.bottom, 16)
            }
        }
        .background(NemaraColor.paper)
        .sheet(isPresented: $showingEditProfile) {
            EditProfileView()
                .environment(env)
        }
        .sheet(isPresented: $showingContactSupport) {
            SupportContactView()
                .environment(env)
        }
        .sheet(isPresented: $showingPrivacy) {
            PrivacyPolicyView()
        }
        .sheet(isPresented: $showingNewPatient) {
            NewPatientView()
                .environment(env)
        }
        .fullScreenCover(item: Binding(
            get: { openPatientId.map(SettingsPatientNav.init) },
            set: { openPatientId = $0?.id }
        )) { wrap in
            PatientShell(patientId: wrap.id)
                .environment(env)
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .alert("Delete your account?", isPresented: $showDeleteConfirm) {
            Button("Delete", role: .destructive) { deleteAccount() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently deletes your account, your loved ones' profiles, cameras, and all data. This can't be undone.")
        }
        .alert("Couldn't delete account", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK", role: .cancel) { deleteError = nil }
        } message: {
            Text(deleteError ?? "")
        }
    }

    /// Run the irreversible account delete. On success `RootView` swaps to
    /// the welcome flow automatically (currentCaregiver becomes nil), so
    /// this view is torn down; on failure we keep the user here and show
    /// the error. `isDeleting` is reset in a `defer` so a thrown error
    /// can't leave the button permanently disabled.
    private func deleteAccount() {
        Task {
            isDeleting = true
            defer { isDeleting = false }
            do {
                try await env.auth.deleteAccount()
            } catch {
                deleteError = error.localizedDescription
            }
        }
    }

    private var caregiverCard: some View {
        Button { showingEditProfile = true } label: {
            NemaraCard(padding: 16) {
                HStack(spacing: 12) {
                    NemaraAvatar(letter: env.auth.currentCaregiver?.displayName.first.map(String.init) ?? "J", size: 56)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(env.auth.currentCaregiver?.displayName ?? "Jane Patel")
                            .font(NemaraFont.title2)
                            .foregroundStyle(NemaraColor.ink)
                            .kerning(-0.3)
                        Text(env.auth.currentCaregiver?.email ?? "jane@patel.co")
                            .font(NemaraFont.caption)
                            .foregroundStyle(NemaraColor.ink3)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(NemaraColor.ink3)
                }
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 16)
    }

    private var patientsCard: some View {
        NemaraCard(padding: 0) {
            VStack(spacing: 0) {
                ForEach(env.api.patients.indices, id: \.self) { i in
                    let p = env.api.patients[i]
                    Button { openPatientId = p.id } label: {
                        HStack(spacing: 12) {
                            NemaraAvatar(letter: p.avatarLetter, size: 40)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(p.fullName).font(NemaraFont.bodySemibold).foregroundStyle(NemaraColor.ink)
                                Text(p.relation.displayName).font(NemaraFont.caption).foregroundStyle(NemaraColor.ink3)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(NemaraColor.ink3)
                        }
                        .padding(12)
                    }
                    .buttonStyle(.plain)
                    if i < env.api.patients.count - 1 {
                        NemaraColor.line.frame(height: 1)
                    }
                }
            }
        }
    }

    private var accountCard: some View {
        NemaraCard(padding: 0) {
            VStack(spacing: 0) {
                Button { showingPrivacy = true } label: {
                    rowChevron(icon: "lock.shield.fill", title: "Privacy & data")
                }
                .buttonStyle(.plain)
                NemaraColor.line.frame(height: 1)
                Button { showingContactSupport = true } label: {
                    rowChevron(icon: "envelope.fill", title: "Contact support")
                }
                .buttonStyle(.plain)
                NemaraColor.line.frame(height: 1)
                Button {
                    Task { await env.auth.signOut() }
                } label: {
                    HStack(spacing: 12) {
                        iconTile("rectangle.portrait.and.arrow.right")
                        Text("Sign out").font(NemaraFont.body).foregroundStyle(NemaraColor.ink)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(NemaraColor.ink3)
                    }
                    .padding(14)
                }
                .buttonStyle(.plain)
                NemaraColor.line.frame(height: 1)
                Button {
                    showDeleteConfirm = true
                } label: {
                    HStack(spacing: 12) {
                        iconTile("trash.fill")
                        Text("Delete account").font(NemaraFont.body).foregroundStyle(NemaraColor.danger)
                        Spacer()
                        if isDeleting {
                            ProgressView()
                        } else {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(NemaraColor.ink3)
                        }
                    }
                    .padding(14)
                }
                .buttonStyle(.plain)
                .disabled(isDeleting)
            }
        }
    }

    // MARK: - helpers

    private func iconTile(_ name: String) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(NemaraColor.paperDim)
            Image(systemName: name)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(NemaraColor.ink2)
        }
        .frame(width: 32, height: 32)
    }

    private func rowChevron(icon: String, title: String) -> some View {
        HStack(spacing: 12) {
            iconTile(icon)
            Text(title).font(NemaraFont.body).foregroundStyle(NemaraColor.ink)
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(NemaraColor.ink3)
        }
        .padding(14)
    }
}

/// `fullScreenCover(item:)` requires `Identifiable`. UUID itself can't
/// safely conform (potential stdlib conflict), so we wrap. Mirrors the
/// private wrapper in RosterView.
private struct SettingsPatientNav: Identifiable, Hashable {
    let id: UUID
}

#if DEBUG
#Preview {
    NavigationStack { AppSettingsView() }
        .environment(AppEnvironment.preview())
}
#endif
