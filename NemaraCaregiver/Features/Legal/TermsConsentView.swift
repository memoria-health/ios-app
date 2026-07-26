import SwiftUI

/// Review-and-accept gate for the Terms of Service + Privacy Notice, presented
/// as a sheet from signup. "I agree" unlocks only after the reader scrolls to
/// the end of BOTH documents; there is no accept-without-reading path. On
/// agree, `onAgree` fires (the signup form marks agreement and can submit) and
/// the sheet dismisses. Cancel returns to the form without agreeing, so signup
/// stays blocked — matching "you cannot complete signup unless you agree."
struct TermsConsentView: View {
    let onAgree: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var selected: String = LegalConstants.documents.first?.id ?? ""
    @State private var reached: Set<String> = []

    private var allReviewed: Bool {
        reached.count >= LegalConstants.documents.count
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Document", selection: $selected) {
                    ForEach(LegalConstants.documents) { doc in
                        Text(reached.contains(doc.id) ? "\(doc.title)  ✓" : doc.title)
                            .tag(doc.id)
                    }
                }
                .pickerStyle(.segmented)
                .padding([.horizontal, .top], 16)

                // Keep every document mounted (so each remembers its scroll +
                // reviewed state); show only the selected one.
                ZStack {
                    ForEach(LegalConstants.documents) { doc in
                        PDFDocumentScroll(resource: doc.resource) {
                            reached.insert(doc.id)
                        }
                        .opacity(selected == doc.id ? 1 : 0)
                        .allowsHitTesting(selected == doc.id)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                VStack(spacing: 10) {
                    if !allReviewed {
                        Text("Scroll to the end of each document to continue.")
                            .font(NemaraFont.caption)
                            .foregroundStyle(NemaraColor.ink2)
                            .frame(maxWidth: .infinity)
                    }
                    NemaraButton("I agree", variant: .primary, size: .lg, block: true) {
                        onAgree()
                        dismiss()
                    }
                    .disabled(!allReviewed)
                    .opacity(allReviewed ? 1 : 0.5)
                }
                .padding(16)
            }
            .background(NemaraColor.paper)
            .navigationTitle("Terms & Privacy")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
