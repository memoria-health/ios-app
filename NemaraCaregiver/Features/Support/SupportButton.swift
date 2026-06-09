import SwiftUI

/// Perpetual floating "Text us" help button, shown on every signed-in screen
/// via an overlay in `RootView`. Tapping opens a one-field chat sheet that
/// posts to `/v1/support` — which emails the founders and (when Twilio is
/// configured) texts them the caregiver's name + number + message, so they
/// can reply to the caregiver's phone directly.
///
/// Positioned as a small bottom-trailing overlay that only occupies its own
/// footprint, so it does NOT wrap the tab bar in a gesture (which would
/// swallow tab taps — see RootView / MainTabView notes). The exact vertical
/// offset may need on-device tuning to sit just above the tab bar.
struct SupportButton: View {
    @State private var showSheet = false

    var body: some View {
        Button {
            showSheet = true
        } label: {
            Image(systemName: "message.fill")
                .font(.system(size: 21, weight: .semibold))
                .foregroundStyle(NemaraColor.actionInk)
                .frame(width: 56, height: 56)
                .background(NemaraColor.terra, in: Circle())
                .shadow(color: NemaraColor.ink.opacity(0.18), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Get help")
        .sheet(isPresented: $showSheet) {
            HelpChatSheet()
        }
    }
}

/// One-field "What do you need help with?" sheet. Reuses the existing
/// `/v1/support` path via `api.sendSupport` (subject is fixed since this is a
/// chat-style entry, not the Settings form).
private struct HelpChatSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var message = ""
    @State private var isSending = false
    @State private var errorMessage: String?
    @State private var successMessage: String?

    private var trimmed: String { message.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSend: Bool { !trimmed.isEmpty && !isSending }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text("What do you need help with?")
                        .font(NemaraFont.title3)
                        .foregroundStyle(NemaraColor.ink)
                    Text("Send us a note and we'll text you back personally.")
                        .font(NemaraFont.bodySmall)
                        .foregroundStyle(NemaraColor.ink2)

                    ZStack(alignment: .topLeading) {
                        if message.isEmpty {
                            Text("Type your message…")
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
                            .frame(minHeight: 160, alignment: .topLeading)
                    }
                    .background(NemaraColor.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous)
                            .strokeBorder(message.isEmpty ? NemaraColor.line : NemaraColor.ink, lineWidth: 1.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous))

                    if let errorMessage {
                        Text(errorMessage)
                            .font(NemaraFont.caption)
                            .foregroundStyle(NemaraColor.danger)
                    } else if let successMessage {
                        Text(successMessage)
                            .font(NemaraFont.caption)
                            .foregroundStyle(NemaraColor.ink2)
                    }
                }
                .padding(16)
            }
            .scrollDismissesKeyboard(.interactively)
            .dismissKeyboardOnTap()
            .background(NemaraColor.paper)
            .navigationTitle("Get help")
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
                subject: "In-app help",
                message: trimmed,
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
    ZStack {
        NemaraColor.paper.ignoresSafeArea()
        SupportButton()
            .environment(AppEnvironment.preview())
    }
}
#endif
