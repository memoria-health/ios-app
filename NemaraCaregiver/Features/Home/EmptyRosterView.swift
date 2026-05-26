import SwiftUI

/// What a brand-new caregiver sees on first sign-in. Replaces the
/// `RosterView`'s patient list with a centered "Add your first patient"
/// card so the next action is the only thing on the screen.
///
/// Not a top-level route: this is a state of the Home tab, rendered
/// inline from `RosterView` when `api.patients.isEmpty`.
struct EmptyRosterView: View {
    @Environment(AppEnvironment.self) private var env
    @Binding var showingNewPatient: Bool

    var body: some View {
        VStack(spacing: 0) {
            roster_largeTitle(sub: "Welcome, \(firstName)", title: "Today")
                .padding(.horizontal, 4)

            Spacer(minLength: 0)

            NemaraCard(padding: NemaraSpacing.lg) {
                VStack(spacing: 16) {
                    concentricRings
                    VStack(spacing: 10) {
                        Text("Add your first patient")
                            .font(NemaraFont.title1)
                            .foregroundStyle(NemaraColor.ink)
                            .kerning(-0.7)
                            .multilineTextAlignment(.center)
                        Text("Add their profile and you'll see everything you're verified to care for, all in one place.")
                            .font(NemaraFont.bodySmall)
                            .foregroundStyle(NemaraColor.ink2)
                            .multilineTextAlignment(.center)
                            .lineSpacing(3)
                            .frame(maxWidth: 280)
                    }
                    NemaraButton("Add a patient", variant: .primary, size: .lg, systemImage: "plus") {
                        showingNewPatient = true
                    }
                    .padding(.top, 4)
                }
                .padding(.vertical, 20)
                .frame(maxWidth: .infinity)
            }
            .padding(.horizontal, 16)

            Spacer(minLength: 0)
        }
        .background(NemaraColor.paper)
    }

    private var firstName: String {
        env.auth.currentCaregiver?.displayName.split(separator: " ").first.map(String.init) ?? "Jane"
    }

    private var concentricRings: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .strokeBorder(i == 2 ? NemaraColor.terra : NemaraColor.terraSoft,
                                  lineWidth: 1)
                    .opacity(i == 2 ? 1 : 0.65)
                    .padding(CGFloat(i) * 14)
            }
            Circle()
                .fill(NemaraColor.terraSoft)
                .padding(42)
            Image(systemName: "plus")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(NemaraColor.terra)
        }
        .frame(width: 128, height: 128)
    }
}

/// Shared large-title layout used by RosterView + EmptyRoster + AppSettings.
/// Lives here so both Roster screens can share the same eye/serif treatment.
@ViewBuilder
func roster_largeTitle(sub: String? = nil, title: String, trailing: (() -> AnyView)? = nil) -> some View {
    HStack(alignment: .lastTextBaseline, spacing: 12) {
        VStack(alignment: .leading, spacing: 6) {
            if let sub {
                Text(sub).nemaraEyebrow()
            }
            Text(title)
                .font(NemaraFont.largeTitle)
                .foregroundStyle(NemaraColor.ink)
                .kerning(-1)
        }
        Spacer()
        if let trailing {
            trailing()
        }
    }
    .padding(.horizontal, 20)
    .padding(.top, 4)
    .padding(.bottom, 16)
}

#if DEBUG
#Preview {
    let env = AppEnvironment.preview()
    env.api.patients = []
    return EmptyRosterView(showingNewPatient: .constant(false))
        .environment(env)
}
#endif
