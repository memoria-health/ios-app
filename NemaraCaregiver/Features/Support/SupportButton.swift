import SwiftUI

/// Perpetual floating "Text us" help button, shown on every signed-in screen
/// via an overlay in `RootView`. Tapping opens a chat-style help sheet that
/// posts to `/v1/support` — which emails the founders the caregiver's name +
/// phone (tap-to-text) + message, so they reply from Messages.
///
/// A footprint-only bottom-trailing overlay (NOT a gesture on the TabView,
/// which would swallow tab taps). Vertical offset may need on-device tuning.
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

/// Compact header form of the same help entry — lives in the top bars
/// (roster header, patient header) instead of floating over content.
/// The perpetual bubble covered charts and review chips; help belongs
/// in chrome, not on top of the patient's day.
struct SupportIconButton: View {
    @State private var showSheet = false

    var body: some View {
        Button {
            showSheet = true
        } label: {
            // Metrics from NemaraHeaderIcon, so this cannot drift away
            // from the actions it sits beside. It used to be a bordered
            // 12pt chip in both headers while every neighbour was a bare
            // 20pt glyph, which read as a different KIND of control
            // rather than a peer.
            Image(systemName: "message.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(NemaraColor.ink)
                .frame(width: NemaraHeaderIcon.hit, height: NemaraHeaderIcon.hit)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Get help")
        .sheet(isPresented: $showSheet) {
            HelpChatSheet()
        }
    }
}

/// Chat-widget styled help sheet: a greeting bubble up top and a message
/// composer pinned to the bottom (like iMessage), so it reads as a live chat
/// rather than a "leave us a message" form. Posts to the existing /v1/support.
private struct HelpChatSheet: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var message = ""
    @State private var sentText = ""
    @State private var isSending = false
    @State private var didSend = false
    @State private var errorMessage: String?

    private var trimmed: String { message.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var canSend: Bool { !trimmed.isEmpty && !isSending && !didSend }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        bubble("What do you need help with?", incoming: true)
                        bubble("Send us a note and we'll text you back instantly.", incoming: true)

                        if didSend {
                            if !sentText.isEmpty { bubble(sentText, incoming: false) }
                            bubble("Got it — we'll text you back shortly.", incoming: true)
                        }

                        if let errorMessage {
                            Text(errorMessage)
                                .font(NemaraFont.caption)
                                .foregroundStyle(NemaraColor.danger)
                                .padding(.top, 4)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(16)
                }

                composer
            }
            .background(NemaraColor.paper)
            .navigationTitle("Memoria support")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(didSend ? "Done" : "Cancel") { dismiss() }
                        .foregroundStyle(NemaraColor.ink2)
                }
            }
        }
    }

    // MARK: - Composer (pinned bottom, iMessage-style)

    private var composer: some View {
        HStack(alignment: .bottom, spacing: 10) {
            TextField("Message…", text: $message, axis: .vertical)
                .lineLimit(1...5)
                .font(NemaraFont.bodyLarge.weight(.regular))
                .foregroundStyle(NemaraColor.ink)
                .tint(NemaraColor.terra)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(NemaraColor.card, in: Capsule())
                .overlay(Capsule().strokeBorder(NemaraColor.line, lineWidth: 1))
                .disabled(didSend)

            Button {
                Task { await send() }
            } label: {
                if isSending {
                    ProgressView().controlSize(.small).frame(width: 34, height: 34)
                } else {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(canSend ? NemaraColor.terra : NemaraColor.ink3)
                }
            }
            .disabled(!canSend)
            .accessibilityLabel("Send")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(NemaraColor.paper)
        .overlay(NemaraColor.line.frame(height: 1), alignment: .top)
    }

    // MARK: - Chat bubble

    private func bubble(_ text: String, incoming: Bool) -> some View {
        HStack {
            if !incoming { Spacer(minLength: 44) }
            Text(text)
                .font(NemaraFont.bodyLarge.weight(.regular))
                .foregroundStyle(incoming ? NemaraColor.ink : NemaraColor.actionInk)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(incoming ? NemaraColor.card : NemaraColor.terra)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .frame(maxWidth: 280, alignment: incoming ? .leading : .trailing)
            if incoming { Spacer(minLength: 44) }
        }
    }

    // MARK: - Send

    private func send() async {
        errorMessage = nil
        let text = trimmed
        isSending = true
        defer { isSending = false }   // always clears the spinner, even on error
        NSLog("[Support] send: POST /v1/support (len=%d) — awaiting response…", text.count)
        do {
            let resp = try await env.api.sendSupport(subject: "In-app help", message: text)
            NSLog("[Support] send: OK — status=%@", resp.status)
            sentText = text
            message = ""
            didSend = true
        } catch {
            // If neither this nor the OK line ever logs, the request is hanging
            // (backend unreachable) rather than erroring.
            NSLog("[Support] send: FAILED — %@", "\(error)")
            errorMessage = error.localizedDescription
        }
    }
}

extension View {
    /// Pins the perpetual help button to the bottom-trailing corner, above the
    /// tab bar. Each top-level surface that should show it applies this —
    /// because a `.fullScreenCover` (the patient cover, the expanded live view)
    /// covers the *presenter's* overlay. So MainTabView AND PatientShell both
    /// add it; the expanded live view intentionally does not.
    func supportButtonOverlay() -> some View {
        overlay(alignment: .bottomTrailing) {
            SupportButton()
                .padding(.trailing, 18)
                .padding(.bottom, 90)
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
