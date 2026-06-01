import SwiftUI

/// Sign-up form: name + email + password (with live checklist) + Terms
/// acceptance + primary CTA. On success the auth flow's
/// `currentCaregiver` flips non-nil and `RootView` cuts to `MainTabView`.
struct SignUpView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var email = ""
    @State private var password = ""
    @State private var agreedToTerms = true
    @State private var errorMessage: String?

    private var passwordValid: Bool {
        password.count >= 8
            && password.range(of: #"[A-Z]"#, options: .regularExpression) != nil
            && password.range(of: #"[a-z]"#, options: .regularExpression) != nil
            && password.range(of: #"\d"#,   options: .regularExpression) != nil
            && password.range(of: #"[^A-Za-z0-9]"#, options: .regularExpression) != nil
    }

    private var canSubmit: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && email.contains("@")
            && passwordValid
            && agreedToTerms
            && !env.auth.isAuthenticating
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 18) {
                    NemaraMark(size: 44)
                    Text("Make a Memoria account.")
                        .font(NemaraFont.largeTitle)
                        .foregroundStyle(NemaraColor.ink)
                        .kerning(-1)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(spacing: 12) {
                    NemaraField("Your name", text: $name, placeholder: "Jane Patel",
                                autocapitalization: .words)
                    NemaraField("Email", text: $email, placeholder: "you@home.com",
                                keyboardType: .emailAddress, autocapitalization: .never)
                    NemaraField("Password", text: $password, placeholder: "8+ chars, mixed case, number, symbol",
                                isSecure: true)
                    NemaraPasswordChecklist(value: password)
                }

                termsRow

                if let errorMessage {
                    Text(errorMessage)
                        .font(NemaraFont.bodySmall)
                        .foregroundStyle(NemaraColor.terra)
                }

                NemaraButton(
                    env.auth.isAuthenticating ? "Creating account…" : "Create account",
                    variant: .primary, size: .lg, block: true,
                    action: submit
                )
                .disabled(!canSubmit)
                .opacity(canSubmit ? 1 : 0.5)

                HStack(spacing: 4) {
                    Text("Already have an account?")
                        .font(NemaraFont.bodySmall)
                        .foregroundStyle(NemaraColor.ink2)
                    NavigationLink {
                        LoginView()
                    } label: {
                        Text("Log in")
                            .font(NemaraFont.bodySmall.weight(.semibold))
                            .foregroundStyle(NemaraColor.terra)
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 4)
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

    // MARK: - subviews

    @ViewBuilder
    private var termsRow: some View {
        HStack(alignment: .top, spacing: 10) {
            Button {
                agreedToTerms.toggle()
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(agreedToTerms ? NemaraColor.action : .clear)
                        .overlay(
                            RoundedRectangle(cornerRadius: 5, style: .continuous)
                                .strokeBorder(agreedToTerms ? .clear : NemaraColor.line, lineWidth: 1.5)
                        )
                        .frame(width: 18, height: 18)
                    if agreedToTerms {
                        Image(systemName: "checkmark")
                            .font(.system(size: 10, weight: .black))
                            .foregroundStyle(NemaraColor.actionInk)
                    }
                }
            }
            .buttonStyle(.plain)

            Text("I agree to the **Terms** and acknowledge the **Privacy Notice**, including how Memoria handles audio and video.")
                .font(NemaraFont.caption)
                .foregroundStyle(NemaraColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(.leading)
        }
    }

    // MARK: - actions

    private func submit() {
        Task {
            do {
                errorMessage = nil
                try await env.auth.signUp(displayName: name, email: email, password: password)
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
    NavigationStack { SignUpView() }
        .environment(AppEnvironment.preview())
}
#endif
