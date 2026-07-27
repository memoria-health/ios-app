import SwiftUI

/// Labeled country picker: a card row showing the current country that opens a
/// searchable sheet of every ISO country. Binds the ISO alpha-2 `code`. Used at
/// patient onboarding and account signup (data-residency `region` is derived
/// from the pick server-side). A searchable sheet — not a 250-item Menu — is the
/// only non-janky way to pick from the full list on iOS.
struct CountryPicker: View {
    @Binding var code: String
    @State private var showing = false

    var body: some View {
        Button {
            showing = true
        } label: {
            HStack {
                Text(Countries.name(for: code))
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
        .sheet(isPresented: $showing) {
            CountryPickerSheet(code: $code)
        }
    }
}

/// Searchable full-country list presented as a sheet. Tapping a row commits the
/// selection and dismisses.
private struct CountryPickerSheet: View {
    @Binding var code: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var results: [Countries.Option] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return Countries.all }
        return Countries.all.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        NavigationStack {
            List(results) { opt in
                Button {
                    code = opt.code
                    dismiss()
                } label: {
                    HStack {
                        Text(opt.name)
                            .foregroundStyle(NemaraColor.ink)
                        Spacer()
                        if opt.code == code {
                            Image(systemName: "checkmark")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(NemaraColor.action)
                        }
                    }
                }
            }
            .listStyle(.plain)
            .searchable(text: $query, prompt: "Search countries")
            .navigationTitle("Country")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .tint(NemaraColor.ink)
                }
            }
        }
    }
}
