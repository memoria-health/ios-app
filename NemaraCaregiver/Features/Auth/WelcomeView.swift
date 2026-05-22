import SwiftUI

/// First screen on a fresh launch. The hero serif headline ("The other
/// 99.9% of care.") plus the warm-cream paper canvas; two CTAs at the
/// bottom — Sign up (primary, large) and Log in (ghost).
struct WelcomeView: View {

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 22) {
                NemaraMark(size: 56)

                VStack(alignment: .leading, spacing: 18) {
                    Text("The other 99.9% of care.")
                        .font(NemaraFont.display)
                        .foregroundStyle(NemaraColor.ink)
                        .kerning(-1.5)
                        .lineSpacing(-2)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Stay close to the people you love, even when you can't be in the room.")
                        .font(NemaraFont.bodyLarge)
                        .foregroundStyle(NemaraColor.ink2)
                        .lineSpacing(4)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 0)

            VStack(spacing: 10) {
                NavigationLink(value: AuthRoute.signUp) {
                    nemaraPrimaryLabel("Create an account")
                }
                .buttonStyle(.plain)
                NavigationLink(value: AuthRoute.login) {
                    nemaraGhostLabel("I already have one")
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 24)
        .padding(.bottom, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NemaraColor.paper)
        .navigationDestination(for: AuthRoute.self) { route in
            switch route {
            case .signUp: SignUpView()
            case .login:  LoginView()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
    }
}

/// Routes inside the auth `NavigationStack`.
enum AuthRoute: Hashable {
    case signUp
    case login
}

// MARK: - small inline label helpers (full-block versions of NemaraButton)

private func nemaraPrimaryLabel(_ title: String) -> some View {
    Text(title)
        .font(NemaraFont.sans(size: 16, weight: .semibold))
        .tracking(-0.1)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .foregroundStyle(NemaraColor.actionInk)
        .background(NemaraColor.action)
        .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous))
}

private func nemaraGhostLabel(_ title: String) -> some View {
    Text(title)
        .font(NemaraFont.sans(size: 14, weight: .semibold))
        .tracking(-0.1)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .foregroundStyle(NemaraColor.ink)
}

#Preview {
    NavigationStack { WelcomeView() }
        .environment(AppEnvironment(auth: MockAuthService(), mockStore: MockStore()))
}
