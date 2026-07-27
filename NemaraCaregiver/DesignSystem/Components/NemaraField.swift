import SwiftUI

/// Labeled text field. Uses an eyebrow above a card-tinted box.
/// - When `text` is non-empty, the border darkens to `ink` for a
///   focused-looking state (the design renders both empty and filled
///   examples; we render filled as the "engaged" tier).
/// - `trailing` slots in a tappable affordance (e.g. "Show" toggle).
struct NemaraField: View {
    let label: String
    @Binding var text: String
    let placeholder: String
    let isSecure: Bool
    let keyboardType: UIKeyboardType
    let autocapitalization: TextInputAutocapitalization
    let trailing: AnyView?
    let hint: String?

    init(
        _ label: String,
        text: Binding<String>,
        placeholder: String = "",
        isSecure: Bool = false,
        keyboardType: UIKeyboardType = .default,
        autocapitalization: TextInputAutocapitalization = .sentences,
        hint: String? = nil,
        @ViewBuilder trailing: () -> some View = { EmptyView() }
    ) {
        self.label = label
        self._text = text
        self.placeholder = placeholder
        self.isSecure = isSecure
        self.keyboardType = keyboardType
        self.autocapitalization = autocapitalization
        self.hint = hint
        let t = trailing()
        // Only wrap into AnyView if the caller provided non-empty content.
        if t is EmptyView {
            self.trailing = nil
        } else {
            self.trailing = AnyView(t)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            NemaraEyebrow(label)
            HStack(spacing: 8) {
                Group {
                    if isSecure {
                        SecureField(placeholder, text: $text)
                    } else {
                        TextField(placeholder, text: $text)
                            .keyboardType(keyboardType)
                            .textInputAutocapitalization(autocapitalization)
                            .autocorrectionDisabled(keyboardType == .emailAddress)
                    }
                }
                .font(NemaraFont.bodyLarge.weight(.regular))
                .foregroundStyle(NemaraColor.ink)
                .tint(NemaraColor.terra)
                // Native keyboard "Done" — the Return key is relabeled and
                // pressing it dismisses the keyboard. No floating toolbar.
                .submitLabel(.done)
                .onSubmit { Self.resignFirstResponder() }

                if let trailing { trailing }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(NemaraColor.card)
            .overlay(
                RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous)
                    .strokeBorder(text.isEmpty ? NemaraColor.line : NemaraColor.ink, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous))

            if let hint {
                Text(hint)
                    .font(NemaraFont.caption)
                    .foregroundStyle(NemaraColor.ink3)
                    .lineSpacing(2)
            }
        }
    }
}

/// Sign-up password live-checklist. Renders five rule rows in a two-column
/// grid; each row darkens to `ink` when its rule passes.
struct NemaraPasswordChecklist: View {
    let value: String

    struct Rule {
        let label: String
        let pass: Bool
    }

    private var rules: [Rule] {
        [
            Rule(label: "At least 8 characters",
                 pass: value.count >= 8),
            Rule(label: "One uppercase letter",
                 pass: value.range(of: #"[A-Z]"#, options: .regularExpression) != nil),
            Rule(label: "One lowercase letter",
                 pass: value.range(of: #"[a-z]"#, options: .regularExpression) != nil),
            Rule(label: "One number",
                 pass: value.range(of: #"\d"#, options: .regularExpression) != nil),
            Rule(label: "One symbol",
                 pass: value.range(of: #"[^A-Za-z0-9]"#, options: .regularExpression) != nil),
        ]
    }

    private let columns: [GridItem] = [
        GridItem(.flexible(), spacing: 14, alignment: .leading),
        GridItem(.flexible(), spacing: 14, alignment: .leading),
    ]

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
            ForEach(0..<rules.count, id: \.self) { i in
                let rule = rules[i]
                HStack(spacing: 6) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(rule.pass ? NemaraColor.success : Color.clear)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4, style: .continuous)
                                    .strokeBorder(rule.pass ? .clear : NemaraColor.line, lineWidth: 1.5)
                            )
                            .frame(width: 14, height: 14)
                        if rule.pass {
                            Image(systemName: "checkmark")
                                .font(.system(size: 8, weight: .black))
                                .foregroundStyle(NemaraColor.paper)
                        }
                    }
                    Text(rule.label)
                        .font(NemaraFont.caption)
                        .foregroundStyle(rule.pass ? NemaraColor.ink : NemaraColor.ink3)
                }
            }
        }
    }
}

#if DEBUG
#Preview {
    struct Demo: View {
        @State private var email = ""
        @State private var password = "Mar9aret!"
        var body: some View {
            VStack(spacing: 14) {
                NemaraField("Email", text: $email, placeholder: "you@home.com",
                            keyboardType: .emailAddress,
                            autocapitalization: .never)
                NemaraField("Password", text: $password, isSecure: true)
                NemaraPasswordChecklist(value: password)
            }
            .padding()
            .background(NemaraColor.paper)
        }
    }
    return Demo()
}
#endif
