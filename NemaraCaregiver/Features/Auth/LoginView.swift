import SwiftUI

/// Login form: email + password + "Keep me signed in" + Forgot password.
struct LoginView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var keepSignedIn = true
    @State private var showPassword = false
    @State private var errorMessage: String?

    private var canSubmit: Bool {
        email.contains("@") && !password.isEmpty && !env.auth.isAuthenticating
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 18) {
                    NemaraMark(size: 44)
                    Text("Welcome back.")
                        .font(NemaraFont.largeTitle)
                        .foregroundStyle(NemaraColor.ink)
                        .kerning(-1)
                }

                VStack(spacing: 12) {
                    NemaraField("Email", text: $email, placeholder: "you@home.com",
                                keyboardType: .emailAddress, autocapitalization: .never)
                    NemaraField("Password", text: $password, placeholder: "Enter your password",
                                isSecure: !showPassword) {
                        Button { showPassword.toggle() } label: {
                            Text(showPassword ? "Hide" : "Show")
                                .font(NemaraFont.captionStrong)
                                .foregroundStyle(NemaraColor.terra)
                        }
                        .buttonStyle(.plain)
                    }
                }

                HStack {
                    Button {
                        keepSignedIn.toggle()
                    } label: {
                        HStack(spacing: 8) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 5, style: .continuous)
                                    .fill(keepSignedIn ? NemaraColor.action : .clear)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                                            .strokeBorder(keepSignedIn ? .clear : NemaraColor.line, lineWidth: 1.5)
                                    )
                                    .frame(width: 18, height: 18)
                                if keepSignedIn {
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 10, weight: .black))
                                        .foregroundStyle(NemaraColor.actionInk)
                                }
                            }
                            Text("Keep me signed in")
                                .font(NemaraFont.bodySmall)
                                .foregroundStyle(NemaraColor.ink2)
                        }
                    }
                    .buttonStyle(.plain)
                    Spacer()
                    Button {
                        // Placeholder for forgot-password flow (will deep-link to Supabase reset).
                    } label: {
                        Text("Forgot password?")
                            .font(NemaraFont.bodySmall.weight(.semibold))
                            .foregroundStyle(NemaraColor.terra)
                    }
                    .buttonStyle(.plain)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .font(NemaraFont.bodySmall)
                        .foregroundStyle(NemaraColor.terra)
                }

                NemaraButton(
                    env.auth.isAuthenticating ? "Signing in…" : "Log in",
                    variant: .primary, size: .lg, block: true,
                    action: submit
                )
                .disabled(!canSubmit)
                .opacity(canSubmit ? 1 : 0.5)

                HStack(spacing: 4) {
                    Text("New here?")
                        .font(NemaraFont.bodySmall)
                        .foregroundStyle(NemaraColor.ink2)
                    NavigationLink {
                        SignUpView()
                    } label: {
                        Text("Create an account")
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

    private func submit() {
        Task {
            do {
                errorMessage = nil
                try await env.auth.signIn(email: email, password: password)
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
    NavigationStack { LoginView() }
        .environment(AppEnvironment.preview())
}
#endif
