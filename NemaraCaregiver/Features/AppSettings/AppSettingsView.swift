import SwiftUI

/// Caregiver-level account settings. Surfaced on the Settings tab of the
/// app shell. Lists patients, notification toggles, account actions.
struct AppSettingsView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var showingDailySummary = false

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                roster_largeTitle(title: "Settings")

                caregiverCard
                Group {
                    NemaraEyebrow("YOUR PATIENTS").frame(maxWidth: .infinity, alignment: .leading)
                    patientsCard
                    NemaraButton("Add another patient", variant: .ghost, size: .sm, systemImage: "plus") {
                        // Reuses RosterView's + sheet — for now this just navigates back to Home tab.
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 16)

                Group {
                    NemaraEyebrow("NOTIFICATIONS").frame(maxWidth: .infinity, alignment: .leading)
                    notificationsCard
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
        .sheet(isPresented: $showingDailySummary) {
            DailySummaryPreviewView()
        }
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var caregiverCard: some View {
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
        .padding(.horizontal, 16)
    }

    private var patientsCard: some View {
        NemaraCard(padding: 0) {
            VStack(spacing: 0) {
                ForEach(env.mockStore.patients.indices, id: \.self) { i in
                    let p = env.mockStore.patients[i]
                    HStack(spacing: 12) {
                        NemaraAvatar(letter: p.avatarLetter, size: 40)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.fullName).font(NemaraFont.bodySemibold).foregroundStyle(NemaraColor.ink)
                            Text(p.relation.rawValue).font(NemaraFont.caption).foregroundStyle(NemaraColor.ink3)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(NemaraColor.ink3)
                    }
                    .padding(12)
                    if i < env.mockStore.patients.count - 1 {
                        NemaraColor.line.frame(height: 1)
                    }
                }
            }
        }
    }

    private var notificationsCard: some View {
        NemaraCard(padding: 0) {
            VStack(spacing: 0) {
                @Bindable var store = env.mockStore
                rowToggle(icon: "bell.fill", title: "Push notifications", isOn: $store.pushEnabled)
                NemaraColor.line.frame(height: 1)
                rowToggle(icon: "phone.fill", title: "Phone calls for critical events", isOn: $store.callEnabled)
                NemaraColor.line.frame(height: 1)
                HStack(spacing: 12) {
                    iconTile("envelope.fill")
                    Text("Daily email summary").font(NemaraFont.body).foregroundStyle(NemaraColor.ink)
                    Spacer()
                    NemaraToggle(isOn: Binding(
                        get: { store.dailyEmailEnabled },
                        set: { newValue in
                            if newValue && !store.dailyEmailEnabled {
                                showingDailySummary = true
                            }
                            store.dailyEmailEnabled = newValue
                        }
                    ))
                }
                .padding(14)
            }
        }
    }

    private var accountCard: some View {
        NemaraCard(padding: 0) {
            VStack(spacing: 0) {
                rowChevron(icon: "lock.shield.fill", title: "Privacy & data")
                NemaraColor.line.frame(height: 1)
                rowChevron(icon: "envelope.fill", title: "Contact support")
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

    private func rowToggle(icon: String, title: String, isOn: Binding<Bool>) -> some View {
        HStack(spacing: 12) {
            iconTile(icon)
            Text(title).font(NemaraFont.body).foregroundStyle(NemaraColor.ink)
            Spacer()
            NemaraToggle(isOn: isOn)
        }
        .padding(14)
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

#Preview {
    NavigationStack { AppSettingsView() }
        .environment({
            let env = AppEnvironment(auth: MockAuthService(), mockStore: MockStore())
            env.auth.currentCaregiver = Caregiver(id: UUID(), displayName: "Jane Patel", email: "jane@patel.co")
            return env
        }())
}
