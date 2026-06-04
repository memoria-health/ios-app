import Foundation
import LiveKit
import SwiftUI
import UIKit

/// SwiftUI bridge for LiveKit's UIKit `VideoView`, plus a small render watchdog.
///
/// ## Render watchdog — why it exists
/// When iOS suspends the app (background / swipe-up), it can reclaim the Metal
/// renderer behind `VideoView` while the LiveKit room + subscribed track stay
/// perfectly healthy. On foreground SwiftUI calls `updateUIView`, but because
/// the track OBJECT is unchanged (`uiView.track !== track` is false) it doesn't
/// re-bind, so the dead renderer is never rebuilt → the tile reads "LIVE" but is
/// black, and nothing else recovers it (every other recovery path is gated on
/// the track being *absent*, and here it's present). This is iOS-client-local:
/// the media still arrives, only this device's view stopped painting — the web
/// client renders the same camera fine.
///
/// The watchdog closes that gap WITHOUT disrupting healthy tiles. It polls the
/// view's own `isRendering` flag and only re-attaches the renderer when a tile
/// that **was** painting has been NOT rendering for `stuckThreshold` seconds
/// continuously. It:
///   - never fires on a painting tile, so normal foregrounds cause no blip;
///   - ignores the initial connect (a tile that has never rendered yet is left
///     alone — it only repairs a tile that went black *after* going live), so it
///     can't fight the first-frame handshake;
///   - is purely local — it re-binds this on-device view to the SAME, still-good
///     track; it never touches the connection, the SFU, or other clients.
///
/// Emits `[watchdog]` NSLogs at went-black / repair / recovered so the behavior
/// can be confirmed from the console.
struct LiveKitVideoView: UIViewRepresentable {
    /// The remote video track to render. nil renders an empty view —
    /// callers should overlay their own "connecting" / "no signal"
    /// affordance when the track is nil.
    var track: VideoTrack?
    /// The camera's LiveKit identity, used only to label watchdog logs.
    var identity: String?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> VideoView {
        let v = VideoView()
        // Fill the box; we crop to the rounded 16:9 frame at the
        // parent. ContentMode is intentionally `.fill` not `.fit`
        // because the wall phone publishes in portrait and the
        // caregiver app renders in landscape — letterboxing would
        // waste half the tile.
        v.layoutMode = .fill
        v.mirrorMode = .off
        context.coordinator.start(view: v, hasTrack: track != nil, identity: identity)
        return v
    }

    func updateUIView(_ uiView: VideoView, context: Context) {
        context.coordinator.identity = identity
        if uiView.track !== track {
            uiView.track = track
            // A real track swap (e.g. the camera republished) is a healthy
            // re-bind, not a stall — reset the watchdog so it doesn't count the
            // transition as black, and so the new track must prove itself live
            // before the watchdog will ever repair it.
            context.coordinator.trackChanged(hasTrack: track != nil)
        } else {
            context.coordinator.hasTrack = (track != nil)
        }
    }

    static func dismantleUIView(_ uiView: VideoView, coordinator: Coordinator) {
        coordinator.stop()
        uiView.track = nil
    }

    /// Polls `VideoView.isRendering` and repairs a stuck tile.
    @MainActor
    final class Coordinator {
        /// Whether this tile is supposed to be painting (a track is bound).
        var hasTrack = false
        /// Camera identity, for log labels only.
        var identity: String?

        private weak var view: VideoView?
        private var timer: Timer?
        /// Did the CURRENT track ever actually render a frame? We only repair a
        /// tile that went black AFTER going live — never one still connecting.
        private var everRendered = false
        /// Start of the current uninterrupted "live-but-not-rendering" stretch.
        private var blackSince: Date?
        /// Last repair, for the cooldown.
        private var lastRepair: Date?
        /// Set after a repair so we can log when frames actually return.
        private var awaitingRenderAfterRepair = false
        /// App-foreground observer — drives the unconditional rebuild that is the
        /// reliable fix for the "black after a quick background" bug.
        private var foregroundObserver: NSObjectProtocol?

        /// Require the tile to be black this long, continuously, before
        /// re-attaching. 2s is comfortably above the normal blips around
        /// connect / track swaps / the post-foreground first-frame gap, while
        /// the `everRendered` guard + cooldown keep it from acting on anything
        /// but a genuine "was live, went black" stall.
        private let stuckThreshold: TimeInterval = 2
        /// Don't repair more than once per this window, so a tile that needs a
        /// beat to recover after a re-attach isn't repaired on a loop.
        private let cooldown: TimeInterval = 5
        /// Poll cadence. 0.5s keeps detection within ~0.5s of the threshold so
        /// recovery feels prompt (vs. the 1s granularity slop before).
        private let pollInterval: TimeInterval = 0.5

        private var logID: String { identity ?? "tile" }

        func start(view: VideoView, hasTrack: Bool, identity: String?) {
            self.view = view
            self.hasTrack = hasTrack
            self.identity = identity
            let t = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
                // The timer fires on the main run loop, so we're already on the
                // main actor — assume it synchronously rather than spawning a
                // Task every tick.
                MainActor.assumeIsolated { self?.tick() }
            }
            RunLoop.main.add(t, forMode: .common)
            timer = t

            // Rebuild the renderer on EVERY foreground. iOS can reclaim the Metal
            // surface on background while the SDK still reports isRendering=true
            // (a black tile the watchdog's detector can't see), so instead of
            // trying to DETECT the dead state we just re-attach on the known
            // trigger — the app returning to the foreground.
            foregroundObserver = NotificationCenter.default.addObserver(
                forName: UIApplication.didBecomeActiveNotification,
                object: nil,
                queue: .main,
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.rebuildOnForeground() }
            }
        }

        func stop() {
            timer?.invalidate()
            timer = nil
            if let foregroundObserver {
                NotificationCenter.default.removeObserver(foregroundObserver)
            }
            foregroundObserver = nil
            view = nil
        }

        func trackChanged(hasTrack: Bool) {
            self.hasTrack = hasTrack
            everRendered = false
            blackSince = nil
            awaitingRenderAfterRepair = false
        }

        private func tick() {
            guard let view, hasTrack else {
                blackSince = nil
                return
            }
            if view.isRendering {
                if awaitingRenderAfterRepair {
                    NSLog("[watchdog] %@ recovered — rendering again after repair", logID)
                    awaitingRenderAfterRepair = false
                } else if blackSince != nil {
                    NSLog("[watchdog] %@ recovered on its own (no repair needed)", logID)
                }
                everRendered = true     // it's alive — remember that
                blackSince = nil        // and reset the black clock
                return
            }
            // Not rendering. Only a tile that WAS live and went black is a real
            // stall; a tile that has never painted yet is just still connecting.
            guard everRendered else { return }
            let now = Date()
            if blackSince == nil {
                blackSince = now
                NSLog("[watchdog] %@ went black while live — will repair if still black in %.0fs", logID, stuckThreshold)
                return
            }
            if let last = lastRepair, now.timeIntervalSince(last) < cooldown {
                return
            }
            if let since = blackSince, now.timeIntervalSince(since) >= stuckThreshold {
                repair(blackFor: now.timeIntervalSince(since))
            }
        }

        private func repair(blackFor: TimeInterval) {
            guard let view, let track = view.track else { return }
            NSLog("[watchdog] %@ REPAIR — re-attaching renderer after %.1fs black", logID, blackFor)
            // iOS reclaimed the renderer; the track is fine, the view just needs
            // a fresh attach. nil-then-reset forces VideoView to rebuild its
            // renderer against the same track. Only ever runs against an
            // already-black tile, so the one visible transition is black → live.
            view.track = nil
            view.track = track
            lastRepair = Date()
            blackSince = nil
            awaitingRenderAfterRepair = true
        }

        /// Unconditionally re-attach the renderer when the app returns to the
        /// foreground — the known trigger for the "black but isRendering=true"
        /// state that the watchdog's detector can't catch. We don't try to DETECT
        /// the black (unreliable); we just rebuild. Costs a brief black→video
        /// flicker on each foreground (acceptable vs. a stuck black tile). A short
        /// delay lets the Metal context settle before we re-attach.
        private func rebuildOnForeground() {
            guard hasTrack else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                MainActor.assumeIsolated {
                    guard let self, let view = self.view, let track = view.track
                    else { return }
                    NSLog("[watchdog] %@ FOREGROUND rebuild — re-attaching renderer", self.logID)
                    view.track = nil
                    view.track = track
                    self.lastRepair = Date()
                    self.blackSince = nil
                    self.awaitingRenderAfterRepair = true
                }
            }
        }
    }
}
