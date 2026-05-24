import LiveKit
import SwiftUI

/// "Live" sub-tab. Phone-call metaphor — the caregiver swipes through
/// a carousel of camera tiles and taps a call button overlaid on the
/// currently-displayed tile to open full-duplex audio with **that**
/// camera. Swiping during an active call transfers the call to the
/// newly-displayed camera.
///
/// Connection lifecycle: connect on appear, disconnect on disappear.
/// The single `env.liveKit` instance handles room switching when the
/// caregiver navigates from one patient to another (`connect` calls
/// `disconnect` first).
struct PatientLiveView: View {
    let patientId: UUID
    @Environment(AppEnvironment.self) private var env

    /// Which camera tile the carousel is currently showing. Drives
    /// both video display and call-routing target.
    @State private var selectedCameraId: UUID?

    /// Lifecycle state of the call. `.idle` means no call in flight;
    /// `.connecting` covers token-mint + mic-publish + first
    /// `/talk/start`; `.active` is the live state where swipes
    /// trigger transfers.
    @State private var callState: CallButton.State = .idle

    /// Error surfaced from any of the LiveKit / network operations.
    /// Mirrored into the tile's bottom-overlay so it's visible
    /// without dismissing the carousel.
    @State private var lkError: String? = nil

    /// Per-second clock for the ON AIR timer label.
    @State private var clockTick: Date = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()
    @State private var callStartedAt: Date? = nil

    /// Tracks the in-flight transfer so we can drop stale responses
    /// (rapid swipes can spawn multiple requests).
    @State private var transferSeq: Int = 0

    /// Which camera is currently in full-screen mode. nil = no full-
    /// screen view active. Driven by the expand-icon tap.
    @State private var fullScreenCameraId: UUID?

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if patient?.camerasPaused == true {
                    pausedCard
                } else if onlineCameras.isEmpty {
                    emptyCard
                } else {
                    cameraCarousel
                }
                camerasCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 16)
        }
        .background(NemaraColor.paper)
        .task(id: patientId) { await bootstrap() }
        .onDisappear { Task { await teardown() } }
        .onReceive(timer) { now in clockTick = now }
        .onChange(of: selectedCameraId) { _, newValue in
            // Swipe transfers the call atomically — the backend
            // `/talk/start` broadcasts `is_active=true` to the new
            // target and `false` to every sibling (including the old
            // target), so we don't need an `/end` between transfers.
            guard callState == .active, let newValue else { return }
            Task { await transferCall(to: newValue) }
        }
        .fullScreenCover(item: Binding(
            get: { fullScreenCameraId.map(IdentifiableUUID.init) },
            set: { fullScreenCameraId = $0?.id },
        )) { wrap in
            fullScreenView(forCameraId: wrap.id)
        }
    }

    // MARK: - Full-screen presentation

    @ViewBuilder
    private func fullScreenView(forCameraId cameraId: UUID) -> some View {
        if let cam = allCameras.first(where: { $0.id == cameraId }),
           let identity = cam.livekitIdentity {
            let track = env.liveKit.videoTracksByIdentity[identity]
            ZStack {
                Color.black.ignoresSafeArea()
                if let track {
                    LiveKitVideoView(track: track)
                        .ignoresSafeArea()
                } else {
                    NemaraCamFeedPlaceholder(hue: 30)
                }
                VStack {
                    HStack {
                        Spacer()
                        Button {
                            fullScreenCameraId = nil
                        } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(12)
                                .background(Color.black.opacity(0.55))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .padding(.trailing, 16)
                        .padding(.top, 16)
                    }
                    Spacer()
                    Text(cam.room)
                        .font(NemaraFont.bodyLarge.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(Color.black.opacity(0.55))
                        .clipShape(Capsule(style: .continuous))
                        .padding(.bottom, 32)
                }
            }
            .statusBarHidden()
        } else {
            // Camera went away mid-presentation (unpaired etc.) —
            // bounce back to the carousel.
            Color.black.ignoresSafeArea().onAppear { fullScreenCameraId = nil }
        }
    }

    /// Local Identifiable wrapper for UUID so .fullScreenCover(item:)
    /// can drive presentation. Same pattern used in RosterView.
    private struct IdentifiableUUID: Identifiable, Hashable {
        let id: UUID
    }

    // MARK: - Lifecycle

    private func bootstrap() async {
        guard patient?.camerasPaused != true else { return }
        do {
            let tok = try await env.api.mintViewerToken(forPatient: patientId)
            await env.liveKit.connect(
                url: tok.url,
                token: tok.token,
                room: "patient_\(patientId.uuidString.lowercased())",
            )
            lkError = nil
            await resolveSelectedCamera()
        } catch {
            lkError = error.localizedDescription
        }
    }

    private func resolveSelectedCamera() async {
        // Server's best guess wins; fall back to the first online
        // camera in the patient's roster.
        let suggested = (try? await env.api.getActiveCamera(forPatient: patientId)) ?? nil
        if let s = suggested, onlineCameras.contains(where: { $0.id == s }) {
            selectedCameraId = s
        } else {
            selectedCameraId = onlineCameras.first?.id
        }
    }

    private func teardown() async {
        // Always cut the call on disappear — leaving the screen is
        // semantically "hanging up" in the phone-call metaphor.
        if callState == .active {
            try? await env.liveKit.publishMicrophone(enable: false)
            try? await env.api.endTalk(forPatient: patientId)
        }
        await env.liveKit.disconnect()
        callState = .idle
        callStartedAt = nil
        selectedCameraId = nil
    }

    // MARK: - Call control

    private func startCall() async {
        guard let cameraId = selectedCameraId else { return }
        guard callState == .idle else { return }
        callState = .connecting
        do {
            // Broadcaster grants over the same room; LiveKitClient
            // disconnects + reconnects to upgrade publish capabilities.
            let tok = try await env.api.mintBroadcasterToken(forPatient: patientId)
            await env.liveKit.connect(
                url: tok.url,
                token: tok.token,
                room: "patient_\(patientId.uuidString.lowercased())",
            )
            try await env.liveKit.publishMicrophone(enable: true)
            try await env.api.startTalk(forPatient: patientId, cameraId: cameraId)
            callState = .active
            callStartedAt = Date()
            lkError = nil
        } catch {
            // Roll back any partial publish so a failed start doesn't
            // leave the mic hot.
            try? await env.liveKit.publishMicrophone(enable: false)
            callState = .idle
            callStartedAt = nil
            lkError = "Call failed: \(error.localizedDescription)"
        }
    }

    private func endCall() async {
        guard callState == .active else { return }
        // Stamp UI immediately so the button reverts the moment the
        // caregiver taps end, even if network is slow.
        callState = .idle
        callStartedAt = nil
        try? await env.liveKit.publishMicrophone(enable: false)
        do {
            try await env.api.endTalk(forPatient: patientId)
        } catch {
            lkError = "End call failed: \(error.localizedDescription)"
        }
    }

    private func transferCall(to cameraId: UUID) async {
        transferSeq &+= 1
        let seq = transferSeq
        do {
            try await env.api.startTalk(forPatient: patientId, cameraId: cameraId)
            // Older transfers may finish after newer ones; only the
            // latest gets to clear the error indicator.
            if seq == transferSeq { lkError = nil }
        } catch {
            if seq == transferSeq {
                lkError = "Transfer failed: \(error.localizedDescription)"
            }
        }
    }

    // MARK: - Tiles

    private var cameraCarousel: some View {
        TabView(selection: tabSelectionBinding) {
            ForEach(onlineCameras) { cam in
                cameraTile(for: cam)
                    .tag(Optional(cam.id))
                    .padding(.bottom, 32)   // headroom for the page-dot indicator
            }
        }
        .frame(height: tileHeight)
        .tabViewStyle(.page(indexDisplayMode: onlineCameras.count > 1 ? .always : .never))
        .indexViewStyle(.page(backgroundDisplayMode: .always))
    }

    /// Coerces the optional to non-optional for `TabView` since
    /// SwiftUI's page style doesn't bind cleanly to `Binding<UUID?>`.
    private var tabSelectionBinding: Binding<UUID?> {
        Binding(
            get: { selectedCameraId },
            set: { selectedCameraId = $0 },
        )
    }

    private func cameraTile(for cam: Camera) -> some View {
        let identity = cam.livekitIdentity
        let videoTrack: VideoTrack? = identity.flatMap { env.liveKit.videoTracksByIdentity[$0] }
        let levels = identity.flatMap { env.liveKit.audioLevels[$0] } ?? []
        let isThisCallTarget = cam.id == selectedCameraId

        // The video render lives in `.background` rather than as a
        // peer in the ZStack. UIKit views inside a SwiftUI ZStack can
        // render above sibling SwiftUI content (an SDK-level layer
        // ordering quirk), which is what made the CallButton vanish
        // the moment the video appeared. As a background layer the
        // UIView is provably below every SwiftUI child in this stack.
        return ZStack {
            VStack {
                HStack {
                    statePill(forCameraWith: videoTrack)
                    Spacer()
                    Button {
                        fullScreenCameraId = cam.id
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(NemaraColor.terraInk)
                            .padding(8)
                            .background(NemaraColor.ink.opacity(0.55))
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                if isThisCallTarget, let err = lkError {
                    Text(err)
                        .font(NemaraFont.caption)
                        .foregroundStyle(NemaraColor.terraInk)
                        .padding(8)
                        .background(NemaraColor.ink.opacity(0.65))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }

                bottomOverlay(cam: cam, levels: levels)
            }
            .padding(10)
        }
        .aspectRatio(16/9, contentMode: .fit)
        .background {
            if let track = videoTrack {
                LiveKitVideoView(track: track)
                    .background(NemaraColor.ink)
            } else {
                NemaraCamFeedPlaceholder(hue: 30)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: NemaraRadius.lg, style: .continuous)
                .strokeBorder(NemaraColor.line, lineWidth: 1)
        )
        .overlay(alignment: .bottom) {
            if isThisCallTarget {
                CallButton(state: callState, onTap: handleCallButtonTap)
                    .offset(y: -10)
            }
        }
    }

    private func bottomOverlay(cam: Camera, levels: [Float]) -> some View {
        HStack(alignment: .bottom) {
            VStack(alignment: .leading, spacing: 2) {
                Text(cam.room)
                    .font(NemaraFont.bodySemibold)
                    .foregroundStyle(NemaraColor.terraInk)
                Text(statusLine(for: cam))
                    .font(NemaraFont.mono(size: 9, weight: .semibold))
                    .tracking(0.5)
                    .foregroundStyle(NemaraColor.terraInk.opacity(0.78))
            }
            Spacer()
            // Waveform is only meaningful when audio is flowing —
            // show it for the active call target only.
            if callState == .active && cam.id == selectedCameraId {
                NemaraWaveform(levels: levels)
                    .frame(width: 100, height: 22)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [NemaraColor.ink.opacity(0.75), .clear],
                startPoint: .bottom, endPoint: .top
            )
        )
    }

    @ViewBuilder
    private func statePill(forCameraWith track: VideoTrack?) -> some View {
        // LIVE pill follows the underlying LiveKit connection state
        // unless THIS tile has no track yet — which means the camera
        // is connected to the room but hasn't published video (e.g.
        // wall phone just paired, hasn't tapped Start).
        switch env.liveKit.state {
        case .connected where track != nil:
            HStack(spacing: 6) {
                NemaraPulse(color: NemaraColor.terraInk, size: 5)
                Text(callState == .active ? "ON AIR" : "LIVE")
                    .font(NemaraFont.mono(size: 9, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(NemaraColor.terraInk)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(callState == .active ? Color(.systemRed) : NemaraColor.terra)
            .clipShape(Capsule(style: .continuous))
        case .connected:
            Text("WAITING")
                .font(NemaraFont.mono(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(NemaraColor.terraInk)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(NemaraColor.ink.opacity(0.55))
                .clipShape(Capsule(style: .continuous))
        case .connecting, .reconnecting:
            Text("CONNECTING")
                .font(NemaraFont.mono(size: 9, weight: .bold))
                .tracking(0.8)
                .foregroundStyle(NemaraColor.terraInk)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(NemaraColor.ink.opacity(0.55))
                .clipShape(Capsule(style: .continuous))
        case .disconnected, .failed:
            EmptyView()
        }
    }

    private func statusLine(for cam: Camera) -> String {
        if callState == .active && cam.id == selectedCameraId {
            guard let startedAt = callStartedAt else { return "ON AIR" }
            let elapsed = Int(clockTick.timeIntervalSince(startedAt))
            return String(format: "ON AIR · %02d:%02d", elapsed / 60, elapsed % 60)
        }
        return "CAM \(String(format: "%02d", cam.displayId))"
    }

    private func handleCallButtonTap() {
        switch callState {
        case .idle: Task { await startCall() }
        case .active: Task { await endCall() }
        case .connecting: break
        }
    }

    // MARK: - Empty / paused / cameras-list

    private var pausedCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: NemaraRadius.lg, style: .continuous)
                .fill(NemaraColor.cardAlt)
                .overlay(
                    RoundedRectangle(cornerRadius: NemaraRadius.lg, style: .continuous)
                        .strokeBorder(NemaraColor.line, lineWidth: 1)
                )
            VStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(NemaraColor.paperDim)
                        .frame(width: 64, height: 64)
                    Image(systemName: "video.slash.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(NemaraColor.ink3)
                }
                VStack(spacing: 6) {
                    Text("Monitoring paused")
                        .font(NemaraFont.title3)
                        .foregroundStyle(NemaraColor.ink)
                        .kerning(-0.3)
                    Text("Cameras are off. Turn monitoring back on in Settings.")
                        .font(NemaraFont.bodySmall)
                        .foregroundStyle(NemaraColor.ink2)
                        .multilineTextAlignment(.center)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 32)
                }
            }
            .padding(.vertical, 36)
        }
        .aspectRatio(16/9, contentMode: .fit)
    }

    private var emptyCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: NemaraRadius.lg, style: .continuous)
                .fill(NemaraColor.cardAlt)
                .overlay(
                    RoundedRectangle(cornerRadius: NemaraRadius.lg, style: .continuous)
                        .strokeBorder(NemaraColor.line, lineWidth: 1)
                )
            VStack(spacing: 10) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(NemaraColor.ink3)
                Text("No cameras online")
                    .font(NemaraFont.title3)
                    .foregroundStyle(NemaraColor.ink)
                Text("Pair a wall phone from Patient Settings to start a call.")
                    .font(NemaraFont.bodySmall)
                    .foregroundStyle(NemaraColor.ink2)
                    .multilineTextAlignment(.center)
            }
            .padding(.vertical, 36)
        }
        .aspectRatio(16/9, contentMode: .fit)
    }

    private var camerasCard: some View {
        let paused = patient?.camerasPaused ?? false
        return NemaraCard(padding: 14) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: paused ? "video.slash" : "wifi")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(paused ? NemaraColor.ink3 : NemaraColor.action)
                    NemaraEyebrow(paused
                                  ? "CAMERAS · PAUSED"
                                  : "CAMERAS · \(onlineCameras.count) ONLINE")
                    Spacer()
                }
                VStack(spacing: 8) {
                    ForEach(allCameras) { cam in
                        HStack(spacing: 10) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 7, style: .continuous)
                                    .fill(NemaraColor.paperDim)
                                Image(systemName: cam.iconName)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(NemaraColor.ink2)
                            }
                            .frame(width: 26, height: 26)
                            Text(cam.room).font(NemaraFont.bodySmall).foregroundStyle(NemaraColor.ink)
                            Spacer()
                            Text(String(format: "Cam %02d", cam.displayId))
                                .font(NemaraFont.monoSmall)
                                .foregroundStyle(NemaraColor.ink3)
                            Circle()
                                .fill(paused ? NemaraColor.ink3 : (cam.online ? NemaraColor.action : NemaraColor.ink3))
                                .frame(width: 6, height: 6)
                        }
                    }
                }
                .opacity(paused ? 0.55 : 1)
            }
        }
    }

    // MARK: - Helpers

    private var tileHeight: CGFloat {
        // 16:9 of the assumed phone width minus horizontal padding,
        // plus headroom for the page-dot indicator. The aspect ratio
        // modifier on the tile clamps the actual video frame.
        let w = UIScreen.main.bounds.width - 32
        return w * 9 / 16 + 36
    }

    // MARK: - Data

    private var patient: Patient? {
        env.api.patients.first(where: { $0.id == patientId })
    }
    private var allCameras: [Camera] {
        env.api.camerasByPatient[patientId] ?? []
    }
    private var onlineCameras: [Camera] {
        allCameras.filter(\.online)
    }
}

#Preview {
    let env = AppEnvironment.preview()
    return PatientLiveView(patientId: env.api.patients[0].id)
        .environment(env)
}
