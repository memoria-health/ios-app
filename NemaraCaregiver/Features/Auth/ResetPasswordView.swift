import SwiftUI

/// Step 2+3 of the forgot-password flow. Reached by tapping the
/// `nemara://reset-password?code=…` link from the recovery email; the
/// `.onOpenURL` handler in `NemaraCaregiverApp` extracts the code and
/// presents this view as a full-screen cover.
///
/// On appear we exchange the code for a recovery session
/// (`exchangeRecoveryCode`). If the exchange fails — expired link,
/// already-consumed token, code missing — we show a "link invalid"
/// state with a way to request a fresh email.
///
/// On submit we call `updatePassword`, which (a) updates the password
/// server-side and (b) runs the same `onAuthenticated` provisioning
/// path used by normal sign-in. After that resolves the auth flow
/// flips `currentCaregiver` non-nil and `RootView` cuts to the main
/// tab, exactly like a fresh login.
struct ResetPasswordView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    let code: String

    @State private var exchanging = true
    @State private var linkValid = false
    @State private var recoveringEmail: String?
    @State private var password = ""
    @State private var confirm = ""
    @State private var submitting = false
    @State private var errorMessage: String?

    private var passwordValid: Bool {
        password.count >= 8
    }

    private var canSubmit: Bool {
        passwordValid && password == confirm && !submitting && !exchanging && linkValid
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 18) {
                        NemaraMark(size: 44)
                        Text(linkValid ? "Set a new password." : "Reset password")
                            .font(NemaraFont.largeTitle)
                            .foregroundStyle(NemaraColor.ink)
                            .kerning(-1)
                    }

                    if exchanging {
                        verifyingBody
                    } else if linkValid {
                        formBody
                    } else {
                        invalidBody
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
            .background(NemaraColor.paper)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(NemaraColor.ink2)
                }
            }
        }
        .task { await exchange() }
    }

    @ViewBuilder
    private var verifyingBody: some View {
        Text("Verifying link…")
            .font(NemaraFont.bodySmall)
            .foregroundStyle(NemaraColor.ink3)
            .padding(.top, 8)
    }

    @ViewBuilder
    private var formBody: some View {
        if let recoveringEmail {
            Text("Resetting password for **\(recoveringEmail)**.")
                .font(NemaraFont.bodySmall)
                .foregroundStyle(NemaraColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
        }

        VStack(spacing: 12) {
            NemaraField(
                "New password",
                text: $password,
                placeholder: "At least 8 characters",
                isSecure: true,
            )
            NemaraField(
                "Confirm password",
                text: $confirm,
                placeholder: "Re-enter it",
                isSecure: true,
            )
        }

        if let errorMessage {
            Text(errorMessage)
                .font(NemaraFont.bodySmall)
                .foregroundStyle(NemaraColor.terra)
        }

        NemaraButton(
            submitting ? "Updating…" : "Set new password",
            variant: .primary, size: .lg, block: true,
            action: submit,
        )
        .disabled(!canSubmit)
        .opacity(canSubmit ? 1 : 0.5)
    }

    @ViewBuilder
    private var invalidBody: some View {
        Text(errorMessage ?? "This reset link is missing, expired, or has already been used.")
            .font(NemaraFont.bodySmall)
            .foregroundStyle(NemaraColor.ink2)
            .fixedSize(horizontal: false, vertical: true)

        Text("Request a fresh link from the sign-in screen.")
            .font(NemaraFont.caption)
            .foregroundStyle(NemaraColor.ink3)

        NemaraButton(
            "Close",
            variant: .primary, size: .lg, block: true,
            action: { dismiss() },
        )
        .padding(.top, 4)
    }

    private func exchange() async {
        defer { exchanging = false }
        do {
            recoveringEmail = try await env.auth.exchangeRecoveryCode(code)
            linkValid = true
        } catch let e as APIError {
            errorMessage = e.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func submit() {
        Task {
            submitting = true
            errorMessage = nil
            defer { submitting = false }
            do {
                try await env.auth.updatePassword(password)
                // `updatePassword` ran `onAuthenticated`, so
                // currentCaregiver is now set and RootView is about to
                // swap to the main tab. Dismiss the cover so we land
                // directly on the home screen.
                dismiss()
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
    ResetPasswordView(code: "preview-code")
        .environment(AppEnvironment.preview())
}
#endif
