import SwiftUI

/// Step 1 of the forgot-password flow. Collects the user's email and
/// kicks off a Supabase recovery email. Supabase intentionally returns
/// success whether or not the email is registered (privacy), so the
/// UI never tells the user whether the address has an account.
///
/// The email link opens `nemara://reset-password?code=…`, which the
/// `.onOpenURL` handler in `NemaraCaregiverApp` routes into
/// `ResetPasswordView`.
struct ForgotPasswordView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var sending = false
    @State private var sent = false
    @State private var errorMessage: String?

    private var canSubmit: Bool {
        email.contains("@") && !sending
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 18) {
                    NemaraMark(size: 44)
                    Text(sent ? "Check your email." : "Reset your password.")
                        .font(NemaraFont.largeTitle)
                        .foregroundStyle(NemaraColor.ink)
                        .kerning(-1)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if sent {
                    sentBody
                } else {
                    formBody
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 28)
        }
        .background(NemaraColor.paper)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(NemaraColor.ink)
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private var formBody: some View {
        Text("Enter the email you signed up with and we'll send you a link to set a new password.")
            .font(NemaraFont.bodySmall)
            .foregroundStyle(NemaraColor.ink2)
            .fixedSize(horizontal: false, vertical: true)

        NemaraField(
            "Email",
            text: $email,
            placeholder: "you@home.com",
            keyboardType: .emailAddress,
            autocapitalization: .never,
        )

        if let errorMessage {
            Text(errorMessage)
                .font(NemaraFont.bodySmall)
                .foregroundStyle(NemaraColor.terra)
        }

        NemaraButton(
            sending ? "Sending…" : "Send reset link",
            variant: .primary, size: .lg, block: true,
            action: submit,
        )
        .disabled(!canSubmit)
        .opacity(canSubmit ? 1 : 0.5)

        HStack(spacing: 4) {
            Text("Remembered it?")
                .font(NemaraFont.bodySmall)
                .foregroundStyle(NemaraColor.ink2)
            Button {
                dismiss()
            } label: {
                Text("Sign in")
                    .font(NemaraFont.bodySmall.weight(.semibold))
                    .foregroundStyle(NemaraColor.terra)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }

    @ViewBuilder
    private var sentBody: some View {
        Text("If **\(email)** is registered, a reset link is on its way. Check your inbox (and spam folder).")
            .font(NemaraFont.bodySmall)
            .foregroundStyle(NemaraColor.ink2)
            .fixedSize(horizontal: false, vertical: true)

        Text("The link expires in 1 hour.")
            .font(NemaraFont.caption)
            .foregroundStyle(NemaraColor.ink3)

        NemaraButton(
            "Back to sign in",
            variant: .primary, size: .lg, block: true,
            action: { dismiss() },
        )
        .padding(.top, 4)
    }

    private func submit() {
        Task {
            sending = true
            errorMessage = nil
            defer { sending = false }
            do {
                try await env.auth.requestPasswordReset(email: email)
                sent = true
            } catch let e as APIError {
                errorMessage = e.errorDescription
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack { ForgotPasswordView() }
        .environment(AppEnvironment.preview())
}
#endif
