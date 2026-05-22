import LiveKit
import SwiftUI

/// SwiftUI bridge for LiveKit's UIKit `VideoView`. The SDK exposes a
/// `track` property on the UIKit view; we update it via
/// `UIViewRepresentable.updateUIView`, which means swapping the
/// underlying track (e.g. the wall phone reconnected and re-published)
/// just works without recreating the view.
///
/// Why a custom wrapper instead of LiveKit's own SwiftUI helpers: in
/// `livekit-client-sdk-swift` 2.x the SwiftUI surface is limited to a
/// `RoomScope` connection-managing component. For us the connection
/// lives in `LiveKitClient` (singleton in `AppEnvironment`), so we
/// only need the render half. Keeping the wrapper here keeps the
/// dependency one layer deep — `PatientLiveView` doesn't import
/// LiveKit directly.
struct LiveKitVideoView: UIViewRepresentable {
    /// The remote video track to render. nil renders an empty view —
    /// callers should overlay their own "connecting" / "no signal"
    /// affordance when the track is nil.
    var track: VideoTrack?

    func makeUIView(context: Context) -> VideoView {
        let v = VideoView()
        // Fill the box; we crop to the rounded 16:9 frame at the
        // parent. ContentMode is intentionally `.fill` not `.fit`
        // because the wall phone publishes in portrait and the
        // caregiver app renders in landscape — letterboxing would
        // waste half the tile.
        v.layoutMode = .fill
        v.mirrorMode = .off
        return v
    }

    func updateUIView(_ uiView: VideoView, context: Context) {
        if uiView.track !== track {
            uiView.track = track
        }
    }
}
