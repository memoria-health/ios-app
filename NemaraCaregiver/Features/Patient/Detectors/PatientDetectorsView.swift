import SwiftUI

/// "Detectors" sub-tab. Lists the patient's full detector set (preset
/// + custom) and lets the caregiver toggle each on/off, tune
/// sensitivity, and add custom ones.
///
/// Extracted from `PatientSettingsView.swift`'s prior `detectorsSection`
/// so detectors get their own first-class tab, matching the web
/// dashboard's `/detectors` page. The per-camera assignment toggles
/// live on the per-camera detail view (Cameras tab), not here — this
/// view is patient-wide.
struct PatientDetectorsView: View {
    let patientId: UUID
    @Environment(AppEnvironment.self) private var env
    @State private var showingAddDetector = false
    @State private var showingLibrary = false

    private var detectors: [Detector] {
        env.api.detectorsByPatient[patientId] ?? []
    }
    private var activeCount: Int { detectors.filter(\.isOn).count }

    // Split preset vs custom so the list mirrors the web dashboard's two
    // grouped "BUILT-IN" / "CUSTOM" sections.
    private var presets: [Detector] { detectors.filter { $0.source == .preset } }
    private var customs: [Detector] { detectors.filter { $0.source == .custom } }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                // Add buttons sit at the TOP so they're reachable without
                // scrolling past a long detector list (a patient can have 15+).
                //
                // The BETA marker lives HERE and on the CUSTOM section header,
                // not on each row. Per-row it was repeated noise that said the
                // same thing four times on this screen.
                HStack(spacing: 8) {
                    NemaraChip("BETA", tone: .terra)
                    Text("Custom detectors are new, so accuracy can vary.")
                        .font(NemaraFont.caption)
                        .foregroundStyle(NemaraColor.ink3)
                        // Wrap rather than widen: an unwrappable child is how
                        // this screen ends up scrolling sideways.
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 16)

                NemaraButton(
                    "Add a custom detector",
                    variant: .secondary,
                    block: true,
                    systemImage: "plus",
                ) {
                    showingAddDetector = true
                }
                .padding(.horizontal, 16)

                NemaraButton(
                    "Add from detection library",
                    variant: .secondary,
                    block: true,
                    systemImage: "square.grid.2x2",
                ) {
                    showingLibrary = true
                }
                .padding(.horizontal, 16)

                if detectors.isEmpty {
                    emptyCard
                } else {
                    list
                }
            }
            .padding(.top, 12)
            // Bottom padding moved here (was on the library button) so the
            // detector list now clears the floating tab bar.
            .padding(.bottom, 40)
        }
        .background(NemaraColor.paper)
        .sheet(isPresented: $showingAddDetector) {
            AddDetectorView(patientId: patientId)
                .trackScreen("add_detector")
        }
        .sheet(isPresented: $showingLibrary) {
            DetectorLibraryView(patientId: patientId, mode: .add)
                .environment(env)
                .trackScreen("detector_library")
        }
    }

    private var emptyCard: some View {
        NemaraCard(padding: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("No detectors yet")
                    .font(NemaraFont.bodySemibold)
                    .foregroundStyle(NemaraColor.ink)
                Text("Add a custom detector to describe in plain language what Memoria should watch for.")
                    .font(NemaraFont.caption)
                    .foregroundStyle(NemaraColor.ink3)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 16)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                NemaraEyebrow("DETECTORS")
                Spacer()
                NemaraChip("\(activeCount) active", tone: .action)
            }
            .padding(.horizontal, 16)

            // Two grouped sections, matching the web dashboard: built-in
            // presets first, then the caregiver's custom detectors.
            detectorSection(
                title: "BUILT-IN",
                rows: presets,
                isFirstSection: true,
                emptyHint: "No built-in detectors yet.",
            )
            detectorSection(
                title: "CUSTOM",
                rows: customs,
                isFirstSection: false,
                emptyHint: "None yet. Add a custom detector with the button above.",
                showsBeta: true,
            )
        }
    }

    @ViewBuilder
    private func detectorSection(
        title: String,
        rows: [Detector],
        isFirstSection: Bool,
        emptyHint: String,
        showsBeta: Bool = false,
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                NemaraEyebrow(title)
                if showsBeta { NemaraChip("BETA", tone: .terra) }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)

            if rows.isEmpty {
                NemaraCard(padding: 14) {
                    Text(emptyHint)
                        .font(NemaraFont.caption)
                        .foregroundStyle(NemaraColor.ink3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 16)
            } else {
                NemaraCard(padding: 0) {
                    VStack(spacing: 0) {
                        ForEach(rows.indices, id: \.self) { i in
                            DetectorRow(
                                patientId: patientId,
                                detector: rows[i],
                                isLast: i == rows.count - 1,
                            )
                            // Welcome-tour marker: the tour's "this is a
                            // detector" pause rings the first row. Frame only.
                            .tutorialTarget(isFirstSection && i == 0 ? .firstDetector : nil)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
    }
}
