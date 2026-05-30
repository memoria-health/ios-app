import SwiftUI

/// Per-patient email-alerts card, mirroring the web dashboard's
/// `EmailAlertsSettings`. Master toggle + a list of additional
/// recipients for THIS patient (the owning caregiver's account email
/// always receives this patient's alerts when enabled, shown read-only
/// at the top). Every mutation PATCHes the patient row through
/// `NemaraAPIClient.updatePatient`; the recipients list is sent in
/// full on every add/remove (server replaces the whole array).
///
/// All state is local to this view. `patient` is read from
/// `env.api.patients` so when `updatePatient` writes back the parent
/// view re-renders automatically.
struct PatientEmailAlertsCard: View {
    @Environment(AppEnvironment.self) private var env
    let patientId: UUID

    @State private var draft = ""
    @State private var busy = false
    @State private var error: String?
    @State private var testStatus: String?

    private var patient: Patient? {
        env.api.patients.first(where: { $0.id == patientId })
    }
    private var enabled: Bool { patient?.emailAlertsEnabled ?? false }
    private var recipients: [String] { patient?.emailAlertRecipients ?? [] }
    private var accountEmail: String {
        env.auth.currentCaregiver?.email ?? "your account"
    }

    var body: some View {
        NemaraCard(padding: 14) {
            VStack(alignment: .leading, spacing: 14) {
                masterRow

                if let error {
                    Text(error)
                        .font(NemaraFont.caption)
                        .foregroundStyle(NemaraColor.danger)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                recipientsBlock
                    .opacity(enabled ? 1 : 0.55)

                Divider().background(NemaraColor.line)

                testRow
            }
        }
        .padding(.horizontal, 16)
    }

    private var masterRow: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 11, style: .continuous)
                    .fill(enabled ? NemaraColor.actionSoft : NemaraColor.paperDim)
                Image(systemName: "envelope.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(enabled ? NemaraColor.action : NemaraColor.ink3)
            }
            .frame(width: 38, height: 38)

            VStack(alignment: .leading, spacing: 3) {
                Text("Send email alerts for this patient")
                    .font(NemaraFont.bodySemibold)
                    .foregroundStyle(NemaraColor.ink)
                Text(enabled
                     ? "Alerts go to your account email plus everyone below."
                     : "When on, every detector event triggers an email to your recipients.")
                    .font(NemaraFont.caption)
                    .foregroundStyle(NemaraColor.ink3)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            NemaraToggle(isOn: Binding(
                get: { enabled },
                set: { newValue in Task { await toggle(to: newValue) } }
            ))
            .disabled(busy)
        }
    }

    private var recipientsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            NemaraEyebrow("RECIPIENTS")

            HStack {
                Text(accountEmail)
                    .font(NemaraFont.bodySmall)
                    .foregroundStyle(NemaraColor.ink)
                Spacer()
                Text("YOUR ACCOUNT")
                    .font(NemaraFont.mono(size: 9, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(NemaraColor.ink3)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(NemaraColor.paperDim)
            .overlay(
                RoundedRectangle(cornerRadius: NemaraRadius.sm, style: .continuous)
                    .strokeBorder(NemaraColor.line, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.sm, style: .continuous))

            ForEach(recipients, id: \.self) { r in
                HStack {
                    Text(r)
                        .font(NemaraFont.bodySmall)
                        .foregroundStyle(NemaraColor.ink)
                    Spacer()
                    Button {
                        Task { await remove(r) }
                    } label: {
                        Text("Remove")
                            .font(NemaraFont.bodySmallStrong)
                            .foregroundStyle(NemaraColor.terra)
                    }
                    .buttonStyle(.plain)
                    .disabled(busy)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(NemaraColor.card)
                .overlay(
                    RoundedRectangle(cornerRadius: NemaraRadius.sm, style: .continuous)
                        .strokeBorder(NemaraColor.line, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.sm, style: .continuous))
            }

            HStack(spacing: 8) {
                TextField("add another email", text: $draft)
                    .font(NemaraFont.bodyLarge.weight(.regular))
                    .keyboardType(.emailAddress)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .foregroundStyle(NemaraColor.ink)
                    .tint(NemaraColor.terra)
                    .submitLabel(.done)
                    .onSubmit { Task { await add() } }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                    .background(NemaraColor.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: NemaraRadius.sm, style: .continuous)
                            .strokeBorder(draft.isEmpty ? NemaraColor.line : NemaraColor.ink, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.sm, style: .continuous))

                Button {
                    Task { await add() }
                } label: {
                    Text("Add")
                        .font(NemaraFont.bodySmallStrong)
                        .foregroundStyle(NemaraColor.ink)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(NemaraColor.cardAlt)
                        .overlay(
                            RoundedRectangle(cornerRadius: NemaraRadius.sm, style: .continuous)
                                .strokeBorder(NemaraColor.line, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.sm, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(busy || draft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private var testRow: some View {
        HStack(spacing: 12) {
            Button {
                Task { await sendTest() }
            } label: {
                if busy {
                    ProgressView().controlSize(.small)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                } else {
                    Text("Send test email")
                        .font(NemaraFont.bodySemibold)
                        .foregroundStyle(NemaraColor.actionInk)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                }
            }
            .background(NemaraColor.action)
            .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.sm, style: .continuous))
            .buttonStyle(.plain)
            .disabled(busy)

            if let testStatus {
                Text(testStatus)
                    .font(NemaraFont.bodySmall)
                    .foregroundStyle(NemaraColor.ink2)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Mutations (optimistic via server PATCH, rollback on error)

    private func toggle(to next: Bool) async {
        error = nil
        busy = true
        defer { busy = false }
        do {
            _ = try await env.api.updatePatient(
                patientId, UpdatePatientRequest(emailAlertsEnabled: next),
            )
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func add() async {
        let email = draft.trimmingCharacters(in: .whitespaces).lowercased()
        guard !email.isEmpty else { return }
        guard isValidEmail(email) else {
            error = "That doesn't look like a valid email address."
            return
        }
        guard email != accountEmail.lowercased(),
              !recipients.contains(where: { $0.lowercased() == email }) else {
            error = "That address is already on the list."
            return
        }
        let next = recipients + [email]
        error = nil
        busy = true
        defer { busy = false }
        do {
            _ = try await env.api.updatePatient(
                patientId, UpdatePatientRequest(emailAlertRecipients: next),
            )
            draft = ""
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func remove(_ email: String) async {
        let next = recipients.filter { $0 != email }
        error = nil
        busy = true
        defer { busy = false }
        do {
            _ = try await env.api.updatePatient(
                patientId, UpdatePatientRequest(emailAlertRecipients: next),
            )
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func sendTest() async {
        error = nil
        testStatus = nil
        busy = true
        defer { busy = false }
        do {
            let response = try await env.api.sendPatientTestEmail(patientId)
            testStatus = response.status
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func isValidEmail(_ s: String) -> Bool {
        let parts = s.split(separator: "@")
        guard parts.count == 2, !parts[0].isEmpty, parts[1].contains(".") else { return false }
        return !s.contains(" ")
    }
}

#if DEBUG
#Preview {
    let env = AppEnvironment.preview()
    return PatientEmailAlertsCard(patientId: env.api.patients[0].id)
        .environment(env)
        .padding(.vertical)
        .background(NemaraColor.paper)
}
#endif
