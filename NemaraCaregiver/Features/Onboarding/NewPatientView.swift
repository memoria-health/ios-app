import SwiftUI

/// "Just page 1" of the patient onboarding flow — the basic profile.
/// Presented as a sheet from Roster's `+` and EmptyRoster's CTA.
struct NewPatientView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var fullName = ""
    @State private var preferredName = ""
    @State private var dateOfBirth = Calendar.current.date(from: DateComponents(year: 1955, month: 1, day: 1)) ?? Date()
    @State private var gender = "Female"
    @State private var relation: Patient.Relation = .parent
    @State private var homeAddress = ""

    private var canSubmit: Bool {
        !fullName.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        intro
                        NemaraField("Full name", text: $fullName, placeholder: "Margaret O'Brien",
                                    autocapitalization: .words)
                        NemaraField("Preferred name", text: $preferredName,
                                    placeholder: "Maggie",
                                    autocapitalization: .words,
                                    hint: "What the people who love them actually call them.")
                        dateOfBirthAndGender
                        relationshipPicker
                        NemaraField("Home address", text: $homeAddress,
                                    placeholder: "84 Birch Lane, Cambridge MA",
                                    hint: "Optional")
                        photoRow
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }

                footer
            }
            .background(NemaraColor.paper)
        }
    }

    // MARK: - sections

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(NemaraColor.ink)
            }
            .buttonStyle(.plain)
            Spacer()
            Text("New patient")
                .font(NemaraFont.bodyLarge.weight(.semibold))
                .foregroundStyle(NemaraColor.ink)
                .kerning(-0.2)
            Spacer()
            // invisible spacer to balance the X
            Image(systemName: "xmark").opacity(0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(NemaraColor.paper)
        .overlay(NemaraColor.line.frame(height: 1), alignment: .bottom)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            NemaraEyebrow("BASIC PROFILE", color: NemaraColor.terra)
            Text("Tell us about your patient.")
                .font(NemaraFont.title1)
                .foregroundStyle(NemaraColor.ink)
                .kerning(-0.8)
                .fixedSize(horizontal: false, vertical: true)
            Text("Just the basics. Their feeds and events appear here automatically once you're added as a caregiver.")
                .font(NemaraFont.bodySmall)
                .foregroundStyle(NemaraColor.ink2)
                .lineSpacing(2)
                .padding(.top, 2)
        }
    }

    private var dateOfBirthAndGender: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                NemaraEyebrow("DATE OF BIRTH")
                DatePicker("", selection: $dateOfBirth, displayedComponents: .date)
                    .datePickerStyle(.compact)
                    .labelsHidden()
                    .tint(NemaraColor.terra)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NemaraColor.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous)
                            .strokeBorder(NemaraColor.line, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 6) {
                NemaraEyebrow("GENDER")
                Menu {
                    ForEach(["Female", "Male", "Non-binary", "Prefer not to say"], id: \.self) { g in
                        Button(g) { gender = g }
                    }
                } label: {
                    HStack {
                        Text(gender)
                            .font(NemaraFont.bodyLarge)
                            .foregroundStyle(NemaraColor.ink)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(NemaraColor.ink3)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(NemaraColor.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous)
                            .strokeBorder(NemaraColor.line, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous))
                }
                .tint(NemaraColor.ink)
            }
        }
    }

    private var relationshipPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            NemaraEyebrow("YOUR RELATIONSHIP")
            FlexibleGrid(spacing: 6) {
                ForEach(Patient.Relation.allCases, id: \.self) { rel in
                    let on = rel == relation
                    Button { relation = rel } label: {
                        Text(rel.rawValue)
                            .font(NemaraFont.bodyMedium)
                            .foregroundStyle(on ? NemaraColor.terraInk : NemaraColor.ink2)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(on ? NemaraColor.terra : .clear)
                            .overlay(
                                Capsule().strokeBorder(on ? NemaraColor.terra : NemaraColor.line, lineWidth: 1)
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var photoRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            NemaraEyebrow("A PHOTO")
            HStack(spacing: 12) {
                NemaraAvatar(letter: String(preferredName.first ?? fullName.first ?? "?"), size: 68)
                HStack {
                    Spacer()
                    Text("+ Upload photo")
                        .font(NemaraFont.bodySmall)
                        .foregroundStyle(NemaraColor.ink3)
                    Spacer()
                }
                .padding(.vertical, 12)
                .background(NemaraColor.card.opacity(0))
                .overlay(
                    RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous)
                        .strokeBorder(NemaraColor.line, style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
                )
            }
        }
    }

    private var footer: some View {
        HStack {
            NemaraButton("Add patient", variant: .primary, block: true, action: submit)
                .disabled(!canSubmit)
                .opacity(canSubmit ? 1 : 0.5)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(NemaraColor.paper)
        .overlay(NemaraColor.line.frame(height: 1), alignment: .top)
    }

    // MARK: - actions

    private func submit() {
        let pref = preferredName.trimmingCharacters(in: .whitespaces).isEmpty
            ? (fullName.split(separator: " ").first.map(String.init) ?? fullName)
            : preferredName
        let newP = Patient(
            id: UUID(),
            fullName: fullName,
            preferredName: pref,
            dateOfBirth: dateOfBirth,
            gender: gender,
            relation: relation,
            homeAddress: homeAddress.isEmpty ? nil : homeAddress,
            state: .calm,
            statusLine: "All quiet",
            lastEventAt: nil,
            batteryPercent: nil
        )
        env.mockStore.addPatient(newP)
        dismiss()
    }
}

/// Tiny flow layout for the relationship chips. SwiftUI's stock
/// `Layout` would do the same, but this keeps the dep footprint small.
struct FlexibleGrid<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        FlowLayout(spacing: spacing) {
            content()
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        var maxXReached: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > maxW {
                x = 0
                y += rowH + spacing
                rowH = 0
            }
            x += sz.width + spacing
            maxXReached = max(maxXReached, x)
            rowH = max(rowH, sz.height)
        }
        return CGSize(width: maxXReached, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX, y: CGFloat = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX {
                x = bounds.minX
                y += rowH + spacing
                rowH = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}

#Preview {
    NewPatientView()
        .environment(AppEnvironment(auth: MockAuthService(), mockStore: MockStore()))
}
