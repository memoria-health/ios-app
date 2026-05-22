import SwiftUI

/// "Live" sub-tab. Single 16:9 feed of whichever room the patient is
/// currently in (mocked here as Living room), plus a Talk-to-room
/// affordance and the camera-status list.
struct PatientLiveView: View {
    let patientId: UUID
    @Environment(AppEnvironment.self) private var env

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
            NemaraCamFeedPlaceholder(hue: 30)
            // LIVE pill
            VStack {
                HStack {
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
                    Spacer()
                    Image(systemName: "arrow.up.left.and.arrow.down.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(NemaraColor.terraInk)
                        .padding(8)
                        .background(NemaraColor.ink.opacity(0.55))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                }
                Spacer()
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(activeRoom)
                            .font(NemaraFont.bodySemibold)
                            .foregroundStyle(NemaraColor.terraInk)
                        Text("CAM 01 · PERSON SEATED")
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
                        .fill(NemaraColor.terraSoft)
                    Image(systemName: "mic.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(NemaraColor.terra)
                }
                .frame(width: 38, height: 38)

                VStack(alignment: .leading, spacing: 2) {
                    Text(patient.map { "Talk to \($0.preferredName)" } ?? "Talk to room")
                        .font(NemaraFont.bodySemibold)
                        .foregroundStyle(NemaraColor.ink)
                    Text("She'll hear you through whichever room she's in.")
                        .font(NemaraFont.caption)
                        .foregroundStyle(NemaraColor.ink3)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                NemaraButton("Talk", variant: .terra, size: .sm, systemImage: "mic.fill") { }
            }
            .padding(14)
        }
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
                            Text(String(format: "Cam %02d", cam.id))
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

    // MARK: - data

    private var patient: Patient? {
        env.mockStore.patients.first(where: { $0.id == patientId })
    }
    private var cameras: [Camera] {
        env.mockStore.cameras[patientId] ?? []
    }
    private var activeRoom: String {
        cameras.first(where: \.online)?.room ?? "Living room"
    }
}

#Preview {
    let env = AppEnvironment(auth: MockAuthService(), mockStore: MockStore())
    return PatientLiveView(patientId: env.mockStore.patients[0].id)
        .environment(env)
}
