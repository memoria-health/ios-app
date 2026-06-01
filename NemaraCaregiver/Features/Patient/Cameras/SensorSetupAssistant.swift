import NetworkExtension
import SafariServices
import SwiftUI

/// "Set up a new sensor camera" helper. Walks the caregiver through
/// joining the camera's temporary setup WiFi network and opening
/// the captive portal where they enter home WiFi credentials.
///
/// The hard part is hidden: `NEHotspotConfigurationManager.shared
/// .apply(_:)` programmatically connects this phone to the camera's
/// open WiFi network ("Memoria-Setup-XXXXXX") with one tap, no
/// detour through Settings.app. After the join succeeds we open
/// http://192.168.4.1/ in an in-app Safari view so the captive
/// portal renders without leaving the app.
///
/// What the caregiver sees:
///   1. Type the 6-character setup code printed on the camera.
///   2. Tap "Connect to Camera". iOS shows its native
///      "Join Wi-Fi Network?" sheet.
///   3. App opens the setup page, caregiver picks home WiFi and
///      types the password, taps Connect.
///   4. Camera joins home WiFi, AP turns off. Caregiver returns
///      to the camera list; the new camera appears within ~60 s.
///
/// Requires the Hotspot Configuration entitlement and the
/// NSLocalNetworkUsageDescription Info.plist key (already present
/// in NemaraCaregiver). The entitlement key is
/// `com.apple.developer.networking.HotspotConfiguration`; if it is
/// missing, `apply` returns a localized error and the assistant
/// falls back to text instructions.
struct SensorSetupAssistant: View {
    @Environment(\.dismiss) private var dismiss

    @State private var code: String = ""
    @State private var state: AssistantState = .composing
    @State private var showingPortal: Bool = false

    enum AssistantState {
        case composing
        case joining
        case joined(ssid: String)
        case error(String)
    }

    private static let _ssidPrefix = "Memoria-Setup"
    private static let _portalUrl = URL(string: "http://192.168.4.1/")!

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    switch state {
                    case .composing:
                        composeForm
                    case .joining:
                        joiningView
                    case .joined(let ssid):
                        joinedView(ssid: ssid)
                    case .error(let message):
                        errorView(message: message)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 24)
            }
            .background(NemaraColor.paper)
            .navigationTitle("Set up sensor camera")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            // When the captive portal closes, the camera is now joining
            // the home WiFi. Dismiss this assistant so the caregiver
            // lands back on the Available cameras list, where the new
            // camera appears within ~60s via the polling loop. iOS does
            // not expose success vs cancel from SFSafariViewController,
            // so any Safari close path collapses to this. If something
            // went wrong, the caregiver re-opens the assistant.
            .sheet(isPresented: $showingPortal, onDismiss: { dismiss() }) {
                SafariView(url: Self._portalUrl)
                    .ignoresSafeArea()
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("HOW IT WORKS").nemaraEyebrow()
            Text("Plug in the camera. It will broadcast a temporary WiFi network. Connect to it, then enter your home WiFi.")
                .font(NemaraFont.bodySmall)
                .foregroundStyle(NemaraColor.ink2)
        }
        .padding(.top, 8)
    }

    private var composeForm: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Setup code")
                    .font(NemaraFont.bodySmallStrong)
                    .foregroundStyle(NemaraColor.ink2)
                Text("The 6-character code printed on the back of the camera, e.g. A4B7C2.")
                    .font(NemaraFont.caption)
                    .foregroundStyle(NemaraColor.ink3)
            }
            TextField("A4B7C2", text: $code)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled(true)
                .font(NemaraFont.mono(size: 22, weight: .regular))
                .padding(.horizontal, 10)
                .padding(.vertical, 9)
                .background(NemaraColor.paperDim)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            NemaraButton(
                "Connect to camera",
                variant: .primary,
                size: .lg,
                block: true,
                systemImage: "wifi",
            ) {
                Task { await connect() }
            }
            .disabled(_normalizedCode().count != 6)
            Text("iOS will ask permission to join the camera's WiFi network. Tap Allow.")
                .font(NemaraFont.caption)
                .foregroundStyle(NemaraColor.ink3)
                .padding(.top, 4)
        }
    }

    private var joiningView: some View {
        VStack(spacing: 14) {
            ProgressView().scaleEffect(1.4).tint(NemaraColor.ink2)
            Text("Joining the camera's setup network...")
                .font(NemaraFont.bodySmall)
                .foregroundStyle(NemaraColor.ink3)
        }
        .frame(maxWidth: .infinity, minHeight: 160)
    }

    private func joinedView(ssid: String) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(NemaraColor.success)
                Text("Connected to \(ssid)")
                    .font(NemaraFont.bodySemibold)
                    .foregroundStyle(NemaraColor.ink)
            }
            Text("Now open the setup page and pick your home WiFi.")
                .font(NemaraFont.bodySmall)
                .foregroundStyle(NemaraColor.ink2)
            NemaraButton(
                "Open setup page",
                variant: .primary,
                size: .lg,
                block: true,
                systemImage: "safari",
            ) {
                showingPortal = true
            }
            Text("After the camera joins your home WiFi, return to this app and you will see it under \"Add a camera.\"")
                .font(NemaraFont.caption)
                .foregroundStyle(NemaraColor.ink3)
                .padding(.top, 4)
        }
    }

    private func errorView(message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(NemaraColor.terra)
                Text("Connection failed")
                    .font(NemaraFont.bodySemibold)
                    .foregroundStyle(NemaraColor.ink)
            }
            Text(message)
                .font(NemaraFont.bodySmall)
                .foregroundStyle(NemaraColor.ink2)
                .fixedSize(horizontal: false, vertical: true)
            VStack(alignment: .leading, spacing: 6) {
                Text("Manual connection")
                    .font(NemaraFont.bodySmallStrong)
                    .foregroundStyle(NemaraColor.ink)
                Text("If the auto-join is not working, you can connect manually:")
                    .font(NemaraFont.caption)
                    .foregroundStyle(NemaraColor.ink2)
                helpLine("1.", "Open Settings, tap Wi-Fi.")
                helpLine("2.", "Connect to \"\(_predictedSsid())\".")
                helpLine("3.", "Open Safari and visit 192.168.4.1.")
            }
            .padding(.top, 8)
            NemaraButton("Try again", variant: .secondary, size: .md) {
                state = .composing
            }
        }
    }

    private func helpLine(_ index: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(index)
                .font(NemaraFont.bodySmallStrong)
                .foregroundStyle(NemaraColor.ink3)
                .frame(width: 18, alignment: .leading)
            Text(text)
                .font(NemaraFont.bodySmall)
                .foregroundStyle(NemaraColor.ink2)
        }
    }

    // ── helpers ──────────────────────────────────────────────────

    private func _normalizedCode() -> String {
        code.uppercased().filter { $0.isLetter || $0.isNumber }
    }

    private func _predictedSsid() -> String {
        let n = _normalizedCode()
        return n.isEmpty ? "\(Self._ssidPrefix)-XXXXXX" : "\(Self._ssidPrefix)-\(n)"
    }

    @MainActor
    private func connect() async {
        let ssid = _predictedSsid()
        state = .joining
        let config = NEHotspotConfiguration(ssid: ssid)
        // joinOnce=true means iOS will not auto-rejoin this open
        // network on future scans; the AP is short-lived anyway and
        // we do not want it competing with the home WiFi.
        config.joinOnce = true
        do {
            try await NEHotspotConfigurationManager.shared.apply(config)
            // .apply succeeds when the user accepts the system
            // prompt AND the phone actually joins. (For an open
            // network, applying without a join would be silently
            // benign; we trust iOS here.)
            state = .joined(ssid: ssid)
        } catch let error as NEHotspotConfigurationError {
            // .alreadyAssociated is success: phone is already on the
            // AP from a prior attempt.
            if error == .alreadyAssociated {
                state = .joined(ssid: ssid)
                return
            }
            // .userDenied means the caregiver tapped Cancel on the
            // system prompt; return to compose state silently.
            if error == .userDenied {
                state = .composing
                return
            }
            // NEHotspotConfigurationError is a raw-Int enum without a
            // NSError bridge or LocalizedError conformance; map each
            // case to a user-readable string explicitly.
            state = .error(Self.describe(error))
        } catch {
            state = .error(error.localizedDescription)
        }
    }

    private static func describe(_ error: NEHotspotConfigurationError) -> String {
        switch error {
        case .invalid:                  return "The setup network configuration was invalid."
        case .invalidSSID:              return "The setup network name is not valid."
        case .invalidWPAPassphrase:     return "The setup network password is not valid."
        case .invalidWEPPassphrase:     return "The setup network password is not valid."
        case .invalidEAPSettings:       return "The setup network's authentication settings are not valid."
        case .invalidHS20Settings:      return "The setup network's Hotspot 2.0 settings are not valid."
        case .invalidHS20DomainName:    return "The setup network's domain name is not valid."
        case .userDenied:               return "The setup network join was canceled."
        case .internal:                 return "iOS could not start the network join."
        case .pending:                  return "Another network join is already in progress."
        case .systemConfiguration:      return "iOS rejected the network configuration."
        case .unknown:                  return "An unknown error occurred while joining the setup network."
        case .joinOnceNotSupported:     return "One-time joins are not supported on this device."
        case .alreadyAssociated:        return "Already connected to the setup network."
        case .applicationIsNotInForeground: return "The app must be in the foreground to join a network."
        @unknown default:               return "Could not join the setup network."
        }
    }
}

/// Thin SwiftUI bridge around SFSafariViewController. The setup
/// page is plain HTTP at a local IP, so SFSafariViewController is
/// fine (no App Transport Security exception needed for in-app
/// browser content).
private struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
