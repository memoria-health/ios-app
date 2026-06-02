import SwiftUI

/// Modal sheet for sending a Contact Support message. Presented from
/// the Settings tab's "Contact support" row. The backend forwards the
/// message via Resend to the support team, with replyTo set to the
/// caregiver's account email.
struct SupportContactView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var subject = ""
    @State private var message = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    private var trimmedSubject: String { subject.trimmingCharacters(in: .whitespaces) }
    private var trimmedMessage: String { message.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var canSend: Bool {
        !trimmedMessage.isEmpty && !isSending
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    NemaraField(
                        "SUBJECT",
                        text: $subject,
                        placeholder: "Optional",
                        autocapitalization: .sentences,
                    )

                    VStack(alignment: .leading, spacing: 6) {
                        NemaraEyebrow("MESSAGE")
                        ZStack(alignment: .topLeading) {
                            if message.isEmpty {
                                Text("Tell us what's on your mind.")
                                    .font(NemaraFont.bodyLarge.weight(.regular))
                                    .foregroundStyle(NemaraColor.ink3)
                                    .padding(.horizontal, 18)
                                    .padding(.vertical, 16)
                            }
                            TextEditor(text: $message)
                                .scrollContentBackground(.hidden)
                                .font(NemaraFont.bodyLarge.weight(.regular))
                                .foregroundStyle(NemaraColor.ink)
                                .tint(NemaraColor.terra)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 8)
                                .frame(minHeight: 180, alignment: .topLeading)
                        }
                        .background(NemaraColor.card)
                        .overlay(
                            RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous)
                                .strokeBorder(message.isEmpty ? NemaraColor.line : NemaraColor.ink, lineWidth: 1.5)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous))
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(NemaraFont.caption)
                            .foregroundStyle(NemaraColor.danger)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    } else if let successMessage {
                        Text(successMessage)
                            .font(NemaraFont.caption)
                            .foregroundStyle(NemaraColor.ink2)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .dismissKeyboardOnTap()
            .background(NemaraColor.paper)
            .navigationTitle("Contact support")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(NemaraColor.ink2)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        Task { await send() }
                    } label: {
                        if isSending {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("Send").fontWeight(.semibold)
                        }
                    }
                    .disabled(!canSend)
                    .foregroundStyle(canSend ? NemaraColor.ink : NemaraColor.ink3)
                }
            }
        }
    }

    private func send() async {
        errorMessage = nil
        successMessage = nil
        isSending = true
        defer { isSending = false }

        do {
            let response = try await env.api.sendSupport(
                subject: trimmedSubject,
                message: trimmedMessage,
            )
            successMessage = response.status
            try? await Task.sleep(nanoseconds: 800_000_000)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#if DEBUG
#Preview {
    SupportContactView()
        .environment(AppEnvironment.preview())
}
#endif
