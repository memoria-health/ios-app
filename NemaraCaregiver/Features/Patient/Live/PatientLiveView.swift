import LiveKit
import SwiftUI

/// "Live" sub-tab. Live feed of whichever wall phone is publishing to
/// the patient's LiveKit room (`patient_<id>`), with a Talk-to-room
/// toggle and the camera-status list.
///
/// Connection lifecycle: connect on appear, disconnect on disappear.
/// The single `env.liveKit` instance handles room switching when the
/// caregiver navigates from one patient to another (`connect` calls
/// `disconnect` first).
struct PatientLiveView: View {
    let patientId: UUID
    @Environment(AppEnvironment.self) private var env
    @State private var lkError: String? = nil
    @State private var talkInFlight: Bool = false
    @State private var talkActiveCameraId: UUID? = nil
    @State private var talkStartedAt: Date? = nil
    @State private var clockTick: Date = Date()
    @State private var talkClockTimer: Timer? = nil

    private let talkClock = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                if patient?.camerasPaused == true {
                    pausedCard
                } else {
                    feedCard
                    talkCard
                }
                camerasCard
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 16)
        }
        .background(NemaraColor.paper)
        .task(id: patientId) {
            await connectIfNeeded()
        }
        .onDisappear {
            Task { await env.liveKit.disconnect() }
            cancelTalkLocally()
        }
        .onReceive(talkClock) { now in
            clockTick = now
        }
    }

    // MARK: - Live connection

    private func connectIfNeeded() async {
        // Skip if monitoring is paused — there's no expected publisher.
        if patient?.camerasPaused == true { return }
        do {
            let tok = try await env.api.mintViewerToken(forPatient: patientId)
            await env.liveKit.connect(
                url: tok.url,
                token: tok.token,
                room: "patient_\(patientId.uuidString.lowercased())",
            )
            lkError = nil
        } catch {
            lkError = error.localizedDescription
        }
    }

    /// Shown in place of the live feed + Talk card when the caregiver
    /// has paused monitoring from Patient Settings. Tap to jump back
    /// to Settings to flip it on.
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

    // MARK: - sections

    private var feedCard: some View {
        ZStack {
            // Render the LiveKit video when we have a subscribed track;
            // otherwise fall back to the placeholder gradient so the
            // tile never visually disappears.
            if let track = env.liveKit.videoTrack {
                LiveKitVideoView(track: track)
                    .background(NemaraColor.ink)
            } else {
                NemaraCamFeedPlaceholder(hue: 30)
            }

            VStack {
                HStack {
                    statePill
                    Spacer()
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NemaraColor.terraInk)
                        .padding(8)
                        .background(NemaraColor.ink.opacity(0.55))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                Spacer()
                if let err = lkError {
                    Text(err)
                        .font(NemaraFont.caption)
                        .foregroundStyle(NemaraColor.terraInk)
                        .padding(8)
                        .background(NemaraColor.ink.opacity(0.65))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 12)
                }
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(activeRoom)
                            .font(NemaraFont.bodySemibold)
                            .foregroundStyle(NemaraColor.terraInk)
                        Text(feedStatusLine)
                            .font(NemaraFont.mono(size: 9, weight: .semibold))
                            .tracking(0.5)
                            .foregroundStyle(NemaraColor.terraInk.opacity(0.78))
                    }
                    Spacer()
                    audioMeter
                }
                .padding(12)
                .frame(maxWidth: .infinity)
                .background(
                    LinearGradient(
                        colors: [NemaraColor.ink.opacity(0.7), .clear],
                        startPoint: .bottom, endPoint: .top
                    )
                )
            }
            .padding(10)
        }
        .aspectRatio(16/9, contentMode: .fit)
        .background(NemaraColor.ink)
        .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: NemaraRadius.lg, style: .continuous)
                .strokeBorder(NemaraColor.line, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var statePill: some View {
        switch env.liveKit.state {
        case .connected:
            HStack(spacing: 6) {
                NemaraPulse(color: NemaraColor.terraInk, size: 5)
                Text("LIVE")
                    .font(NemaraFont.mono(size: 9, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(NemaraColor.terraInk)
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .background(NemaraColor.terra)
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

    private var feedStatusLine: String {
        switch env.liveKit.state {
        case .connected:
            return talkStartedAt != nil ? "ON AIR · TALKING" : "SUBSCRIBED · VIEWING"
        case .connecting: return "CONNECTING…"
        case .reconnecting: return "RECONNECTING…"
        case .disconnected: return "OFFLINE"
        case .failed: return "ERROR"
        }
    }

    private var audioMeter: some View {
        HStack(alignment: .bottom, spacing: 2) {
            ForEach([3, 6, 4, 9, 5, 8, 4], id: \.self) { v in
                Capsule()
                    .fill(NemaraColor.terraInk)
                    .frame(width: 2, height: CGFloat(v) * 1.6)
                    .opacity(0.85)
            }
        }
        .frame(height: 16)
    }

    private var talkCard: some View {
        NemaraCard(padding: 0) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(talkStartedAt != nil ? NemaraColor.terra : NemaraColor.terraSoft)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(talkStartedAt != nil ? NemaraColor.terraInk : NemaraColor.terra)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text(talkTitle)
                        .font(NemaraFont.bodySemibold)
                        .foregroundStyle(NemaraColor.ink)
                    Text(talkSubtitle)
                        .font(NemaraFont.caption)
                        .foregroundStyle(NemaraColor.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                NemaraButton(
                    talkStartedAt != nil ? "End" : "Talk",
                    variant: .terra,
                    size: .sm,
                    systemImage: talkStartedAt != nil ? "stop.fill" : "mic.fill",
                ) {
                    Task { await toggleTalk() }
                }
                .disabled(talkInFlight || env.liveKit.state != .connected)
            }
            .padding(14)
        }
    }

    private var talkTitle: String {
        if let startedAt = talkStartedAt {
            let elapsed = Int(clockTick.timeIntervalSince(startedAt))
            let mm = elapsed / 60
            let ss = elapsed % 60
            return String(format: "ON AIR · %02d:%02d", mm, ss)
        }
        return patient.map { "Talk to \($0.preferredName)" } ?? "Talk to room"
    }

    private var talkSubtitle: String {
        if talkStartedAt != nil {
            if let camID = talkActiveCameraId, let cam = cameras.first(where: { $0.id == camID }) {
                return "Routed to \(cam.room)."
            } else {
                return "Routed to all rooms."
            }
        }
        return "She'll hear you through whichever room she's in."
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
                                  : "CAMERAS · \(cameras.filter(\.online).count) ONLINE")
                    Spacer()
                    if !paused {
                        Text("PING 14MS").font(NemaraFont.monoSmall).foregroundStyle(NemaraColor.ink3)
                    }
                }
                VStack(spacing: 8) {
                    ForEach(cameras) { cam in
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

    // MARK: - Talk (Phase 3)

    private func toggleTalk() async {
        if talkStartedAt == nil {
            await startTalk()
        } else {
            await endTalk()
        }
    }

    private func startTalk() async {
        guard !talkInFlight else { return }
        talkInFlight = true
        defer { talkInFlight = false }
        do {
            // Mint a broadcaster JWT first; reconnect with the new
            // grants. Same room, so existing video subscription is
            // preserved by LiveKitClient.connect() (which disconnects
            // the prior session first — see LiveKitClient.connect).
            let tok = try await env.api.mintBroadcasterToken(forPatient: patientId)
            await env.liveKit.connect(
                url: tok.url,
                token: tok.token,
                room: "patient_\(patientId.uuidString.lowercased())",
            )
            try await env.liveKit.publishMicrophone(enable: true)
            let response = try await env.api.startTalk(forPatient: patientId)
            talkActiveCameraId = response.activeCameraId
            talkStartedAt = Date()
            lkError = nil
        } catch {
            lkError = "Talk failed: \(error.localizedDescription)"
            // Best-effort: ensure mic is off if publishMicrophone
            // succeeded before startTalk failed.
            try? await env.liveKit.publishMicrophone(enable: false)
        }
    }

    private func endTalk() async {
        guard !talkInFlight else { return }
        talkInFlight = true
        defer { talkInFlight = false }
        // Always try to clean up the mic + server side; surface but
        // don't block on errors — the caregiver expects the button to
        // visibly stop talk.
        try? await env.liveKit.publishMicrophone(enable: false)
        do {
            try await env.api.endTalk(forPatient: patientId)
        } catch {
            lkError = "End talk failed: \(error.localizedDescription)"
        }
        cancelTalkLocally()
    }

    private func cancelTalkLocally() {
        talkStartedAt = nil
        talkActiveCameraId = nil
    }

    // MARK: - data

    private var patient: Patient? {
        env.api.patients.first(where: { $0.id == patientId })
    }
    private var cameras: [Camera] {
        env.api.camerasByPatient[patientId] ?? []
    }
    private var activeRoom: String {
        cameras.first(where: \.online)?.room ?? "Living room"
    }
}

#Preview {
    let env = AppEnvironment.preview()
    return PatientLiveView(patientId: env.api.patients[0].id)
        .environment(env)
}
