import SwiftUI

/// Modal sheet for editing the signed-in caregiver's name, email, and
/// phone. Presented from both the Roster top-right avatar and the
/// Settings tab's caregiver card.
///
/// Save behavior:
/// - Name and phone are written via PATCH /v1/me. The returned row
///   replaces `currentCaregiver` in place so the UI refreshes without
///   a full bootstrap.
/// - Email is changed via Supabase Auth's secure-email-change flow.
///   The new address only becomes live after the user clicks the link
///   Supabase sends them, at which point a DB trigger mirrors the new
///   address into `caregivers.email`. Until then the displayed email
///   stays the old one (intentional, not a bug).
struct EditProfileView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var email = ""
    @State private var phone = ""
    @State private var isHydrated = false
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    NemaraField(
                        "NAME",
                        text: $name,
                        placeholder: "Your name",
                        autocapitalization: .words,
                    )

                    NemaraField(
                        "EMAIL",
                        text: $email,
                        placeholder: "you@home.com",
                        keyboardType: .emailAddress,
                        autocapitalization: .never,
                        hint: emailChanged
                            ? "We'll send a confirmation link to your new email. Your address updates once you click it."
                            : nil,
                    )

                    NemaraField(
                        "PHONE",
                        text: $phone,
                        placeholder: "(555) 123-4567",
                        keyboardType: .phonePad,
                        autocapitalization: .never,
                    )

                    if let errorMessage {
                        Text(errorMessage)
                            .font(NemaraFont.caption)
                            .foregroundStyle(NemaraColor.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(16)
            }
            .background(NemaraColor.paper)
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(NemaraColor.ink2)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await save() }
                    } label: {
                        if isSaving {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Save").fontWeight(.semibold)
                        }
                    }
                    .disabled(!canSave)
                    .foregroundStyle(canSave ? NemaraColor.ink : NemaraColor.ink3)
                }
            }
            .onAppear(perform: hydrate)
        }
    }

    private func hydrate() {
        guard !isHydrated, let me = env.auth.currentCaregiver else { return }
        name = me.displayName
        email = me.email
        phone = me.phone ?? ""
        isHydrated = true
    }

    private var trimmedName: String { name.trimmingCharacters(in: .whitespaces) }
    private var trimmedEmail: String { email.trimmingCharacters(in: .whitespaces) }
    private var trimmedPhone: String { phone.trimmingCharacters(in: .whitespaces) }

    private var nameChanged: Bool {
        guard let me = env.auth.currentCaregiver else { return false }
        return trimmedName != me.displayName
    }

    private var emailChanged: Bool {
        guard let me = env.auth.currentCaregiver else { return false }
        return trimmedEmail.lowercased() != me.email.lowercased()
    }

    private var phoneChanged: Bool {
        guard let me = env.auth.currentCaregiver else { return false }
        return trimmedPhone != (me.phone ?? "")
    }

    private var hasChanges: Bool { nameChanged || emailChanged || phoneChanged }

    /// Phone is required (mirrors signup): at least 10 digits once non-digit
    /// characters are stripped. The backend normalizes the format to E.164.
    private var phoneValid: Bool {
        trimmedPhone.filter(\.isNumber).count >= 10
    }

    private var isValid: Bool {
        guard !trimmedName.isEmpty else { return false }
        guard trimmedEmail.contains("@"), trimmedEmail.contains(".") else { return false }
        guard phoneValid else { return false }
        return true
    }

    private var canSave: Bool {
        isHydrated && hasChanges && isValid && !isSaving
    }

    private func save() async {
        errorMessage = nil
        isSaving = true
        defer { isSaving = false }

        do {
            if nameChanged || phoneChanged {
                let updated = try await env.api.updateMe(
                    displayName: nameChanged ? trimmedName : nil,
                    phone: phoneChanged ? (trimmedPhone.isEmpty ? nil : trimmedPhone) : nil,
                )
                env.auth.currentCaregiver = updated
            }
            if emailChanged {
                try await env.auth.requestEmailChange(trimmedEmail)
            }
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#if DEBUG
#Preview {
    EditProfileView()
        .environment(AppEnvironment.preview())
}
#endif
