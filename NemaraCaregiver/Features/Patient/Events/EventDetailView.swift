import AVKit
import SwiftUI

/// Step 1 of 2 of the event review flow. Shows the title block, a video
/// clip (safety only), and Nemara's VLM-written narrative of what it
/// saw. Tapping "Review this event →" advances to `EventReviewView`.
struct EventDetailView: View {
    let event: DetectionEvent
    let patientId: UUID
    /// Called after the user submits a review. Set by the events list
    /// so submitting can dismiss the whole sheet (back to the events
    /// page), not just pop one level back to this detail view. Nil
    /// when there's no enclosing list — `EventReviewView` falls back
    /// to a plain `dismiss()` in that case.
    var onReviewSubmitted: (() -> Void)? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var env

    /// Resolved signed URL for the archived clip. Loaded lazily in
    /// `.task` once the view appears and `event.hasClip` is true.
    @State private var clipURL: URL?
    /// `nil` = haven't tried yet; `false` = backend said not-ready
    /// (409); `true` = we have a URL.
    @State private var clipResolutionState: ClipResolutionState = .pending
    /// The single AVPlayer for the clip. Created ONCE when the URL
    /// resolves and held in @State, so the frequent re-renders of this
    /// view (the events list polls every 20s, paused or not) don't
    /// rebuild the player and restart/kill playback. The old inline
    /// `AVPlayer(url:)` in the body was recreated on every render, which
    /// made the clip "close" mid-watch at ~20s.
    @State private var player: AVPlayer?

    private enum ClipResolutionState: Equatable {
        case pending
        case generating
        case loaded(URL)
        case notReady
        case failed(String)
    }

    private var tone: Color {
        event.category == .safety ? NemaraColor.terra : NemaraColor.sky
    }
    private var toneSoft: Color {
        event.category == .safety ? NemaraColor.terraSoft : NemaraColor.skySoft
    }
    private var categoryLabel: String {
        event.category == .safety ? "SAFETY" : "ROUTINE"
    }

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    titleBlock
                    clipView
                    narrativeCard
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 100)
                .padding(.top, 6)
            }

            footer
        }
        .background(NemaraColor.paper)
        .task(id: event.id) {
            // Archive runs ~25-45s after the event fires (post-15s
            // buffer + per-frame annotation + upload). Poll the clip
            // URL endpoint until it's ready so the placeholder swaps
            // to the video as soon as the backend finishes archiving.
            // We stop polling on success, on a non-recoverable error,
            // or when the view goes away (task cancellation).
            while !Task.isCancelled {
                if !event.hasClip {
                    clipResolutionState = .generating
                }
                do {
                    if let url = try await env.api.clipURL(forEvent: event.id) {
                        if player == nil { player = AVPlayer(url: url) }
                        clipResolutionState = .loaded(url)
                        return
                    }
                    clipResolutionState = .generating
                } catch {
                    clipResolutionState = .failed(error.localizedDescription)
                    return
                }
                try? await Task.sleep(for: .seconds(3))
            }
        }
        .navigationTitle("Event detail")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Text("1 / 2")
                    .font(NemaraFont.mono(size: 10, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(NemaraColor.ink3)
            }
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(NemaraColor.ink)
                }
            }
        }
    }

    // MARK: - sections

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(toneSoft)
                    Image(systemName: event.iconName)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(tone)
                }
                .frame(width: 28, height: 28)
                Text(categoryLabel)
                    .font(NemaraFont.mono(size: 10, weight: .bold))
                    .tracking(0.7)
                    .foregroundStyle(tone)
            }
            Text(event.title)
                .font(NemaraFont.title1)
                .kerning(-0.8)
                .foregroundStyle(NemaraColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("\(event.location) · \(event.time)")
                .font(NemaraFont.bodySmall)
                .foregroundStyle(NemaraColor.ink2)
        }
    }

    @ViewBuilder
    private var clipView: some View {
        ZStack {
            switch clipResolutionState {
            case .pending:
                clipPlaceholder(label: "Loading clip…")
            case .generating:
                clipPlaceholder(label: "Generating clip…")
            case .notReady:
                clipPlaceholder(label: "Clip processing…")
            case .failed(let msg):
                clipPlaceholder(label: msg)
            case .loaded:
                // Reuse the @State player — never `AVPlayer(url:)` inline here,
                // or a re-render rebuilds it and playback dies mid-clip.
                if let player {
                    VideoPlayer(player: player)
                        .accessibilityLabel("Event clip from \(event.location)")
                } else {
                    clipPlaceholder(label: "Loading clip…")
                }
            }
        }
        .aspectRatio(16/9, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: NemaraRadius.lg, style: .continuous)
                .strokeBorder(NemaraColor.line, lineWidth: 1)
        )
    }

    /// Skeleton state shown while the signed URL is being fetched or
    /// when the archival isn't done yet. Mirrors the visual language
    /// of the live-cam placeholder so the event detail stays
    /// recognizable across the three states.
    private func clipPlaceholder(label: String) -> some View {
        ZStack {
            NemaraCamFeedPlaceholder(hue: 30)
            VStack(spacing: 8) {
                Image(systemName: "film")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(NemaraColor.terraInk.opacity(0.85))
                Text(label)
                    .font(NemaraFont.mono(size: 10, weight: .semibold))
                    .tracking(0.4)
                    .foregroundStyle(NemaraColor.terraInk)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .background(NemaraColor.ink.opacity(0.55))
                    .clipShape(Capsule(style: .continuous))
            }
        }
    }

    private var narrativeCard: some View {
        NemaraCard(padding: 14) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NemaraColor.ink3)
                    NemaraEyebrow("WHAT MEMORIA SAW")
                }
                Text(event.narrative)
                    .font(NemaraFont.bodySmallStrong.weight(.regular))
                    .foregroundStyle(NemaraColor.ink)
                    .lineSpacing(5)
            }
            // Always fill the available width so the card matches the clip
            // above it, regardless of how short/long the narrative is —
            // NemaraCard otherwise shrinks to its content's intrinsic width.
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var footer: some View {
        HStack {
            NavigationLink {
                EventReviewView(
                    event: event,
                    patientId: patientId,
                    onSubmitted: onReviewSubmitted,
                )
            } label: {
                Text("Review this event →")
                    .font(NemaraFont.sans(size: 16, weight: .semibold))
                    .tracking(-0.1)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .foregroundStyle(NemaraColor.actionInk)
                    .background(NemaraColor.action)
                    .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(NemaraColor.paper)
        .overlay(NemaraColor.line.frame(height: 1), alignment: .top)
    }
}

#if DEBUG
#Preview {
    let env = AppEnvironment.preview()
    let pid = env.api.patients[0].id
    return NavigationStack {
        EventDetailView(event: env.api.eventsByPatient[pid]![0], patientId: pid)
    }
    .environment(env)
}
#endif
