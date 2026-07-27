import SwiftUI

/// Two-stage custom-detector creation (parity with the web flow):
///   Stage 1 (entry)  — name + optional note + a plain-English prompt.
///   Stage 2 (review) — the LLM-inferred fields (type, schedule window
///                      for absence detectors, category, icon),
///                      editable, before Create.
/// Sensitivity is inferred + sent silently (tunable later from the
/// detector's settings); where/when default server-side.
struct AddDetectorView: View {
    let patientId: UUID
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    private enum Stage { case entry, review }

    // Curated icons (match backend _ALLOWED_ICONS). SF Symbols.
    private let iconOptions = [
        "eye", "figure.fall", "figure.walk.motion", "door.left.hand.open",
        "pills", "fork.knife", "bed.double", "shower", "tv", "drop", "flame",
        "exclamationmark.triangle", "heart", "person", "cup.and.saucer",
        "moon", "sun.max", "clock", "bell", "car",
    ]

    // Human-friendly labels for the icon picker. The raw SF Symbol names
    // (e.g. "figure.walk.motion") are developer strings and read as
    // gibberish to caregivers, so the picker shows these instead while
    // still storing/sending the symbol name. Any inferred icon outside
    // this curated set falls back to `prettifyIconName`.
    private static let iconLabels: [String: String] = [
        "eye": "Watching",
        "figure.fall": "Fall",
        "figure.walk.motion": "Walking",
        "door.left.hand.open": "Door",
        "pills": "Medication",
        "fork.knife": "Eating",
        "bed.double": "Bed / Sleep",
        "shower": "Shower",
        "tv": "TV",
        "drop": "Water",
        "flame": "Stove / Fire",
        "exclamationmark.triangle": "Warning",
        "heart": "Health",
        "person": "Person",
        "cup.and.saucer": "Drink",
        "moon": "Night",
        "sun.max": "Daytime",
        "clock": "Time",
        "bell": "Alert",
        "car": "Outing",
    ]

    /// Friendly display name for an SF Symbol. Falls back to stripping
    /// common prefixes/suffixes and Title-Casing so even an inferred icon
    /// that isn't in `iconLabels` never shows raw dotted developer text.
    private func iconLabel(_ symbol: String) -> String {
        if let friendly = Self.iconLabels[symbol] { return friendly }
        let cleaned = symbol
            .replacingOccurrences(of: "figure.", with: "")
            .replacingOccurrences(of: "person.", with: "")
            .replacingOccurrences(of: ".fill", with: "")
            .replacingOccurrences(of: ".", with: " ")
        let words = cleaned.split(separator: " ").map {
            $0.prefix(1).uppercased() + $0.dropFirst()
        }
        return words.isEmpty ? symbol : words.joined(separator: " ")
    }
    private let dayLabels = ["M", "T", "W", "T", "F", "S", "S"] // 0=Mon..6=Sun

    @State private var stage: Stage = .entry
    @State private var busy = false
    @State private var error: String?
    /// Create-as-draft (item C2): the just-created OFF detector, presented in
    /// the detail sheet for review before the caregiver turns it on.
    @State private var createdDetector: Detector?

    // Entry
    @State private var name = ""
    @State private var note = ""
    @State private var prompt = ""

    // Inferred + editable
    @State private var alertTrigger: Detector.AlertTrigger = .leading
    @State private var isSustained = false
    @State private var durationSeconds: Int? = nil
    @State private var category: Detector.Category = .safety
    @State private var icon = "eye"
    // Inferred only for `.state` (continuous) detectors — the rising-edge
    // episode gap in seconds. Sent on create so the backend collapses an
    // ongoing activity ("watching TV") into one event instead of one per tick.
    @State private var episodeGapSeconds: Int? = nil
    @State private var sensitivity: Detector.Sensitivity = .standard
    @State private var cadence: Detector.ScheduleConfig.Cadence = .daily
    /// Compiled-behavior preview from /infer (customs visibility).
    @State private var plan: DetectorPlan?
    @State private var days: Set<Int> = []
    @State private var windowStart = Self.defaultTime(9, 0)
    @State private var windowEnd = Self.defaultTime(17, 0)
    @State private var deadline = Self.defaultTime(17, 0)
    @State private var timesUncertain = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let error { errorBanner(error) }
                        intro
                        nameInput
                        noteInput
                        promptInput
                        if stage == .review { inferredSection }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }
                .scrollDismissesKeyboard(.interactively)
                footer
            }
            .background(NemaraColor.paper)
            // The prompt is multi-line (Return inserts line breaks), so it
            // has no Return-key "Done"; dismiss it by swiping the scroll
            // view or tapping outside.
            .dismissKeyboardOnTap()
            // Review the OFF draft in the detail sheet, then closing it
            // returns to the detector list (item C2).
            .sheet(item: $createdDetector, onDismiss: { dismiss() }) { det in
                DetectorDetailSheet(patientId: patientId, detector: det)
            }
        }
    }

    // MARK: - chrome

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(NemaraColor.ink)
            }
            .buttonStyle(.plain)
            Spacer()
            Text("New detector")
                .font(NemaraFont.bodyLarge.weight(.semibold))
                .foregroundStyle(NemaraColor.ink)
            Spacer()
            Image(systemName: "xmark").opacity(0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .overlay(NemaraColor.line.frame(height: 1), alignment: .bottom)
    }

    private func errorBanner(_ msg: String) -> some View {
        Text(msg)
            .font(NemaraFont.caption)
            .foregroundStyle(NemaraColor.terra)
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(NemaraColor.terraSoft)
            .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.sm, style: .continuous))
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            NemaraEyebrow("CUSTOM DETECTION", color: NemaraColor.terra)
            Text("What should Memoria watch for?")
                .font(NemaraFont.title1)
                .kerning(-0.7)
                .foregroundStyle(NemaraColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Describe it in plain words. Memoria figures out the rest — including whether it's a live alert or a daily/weekly check.")
                .font(NemaraFont.bodySmall)
                .foregroundStyle(NemaraColor.ink2)
                .lineSpacing(2)
        }
    }

    private var nameInput: some View {
        VStack(alignment: .leading, spacing: 6) {
            NemaraEyebrow("NAME")
            textField("e.g. Medication check", text: $name)
        }
    }

    private var noteInput: some View {
        VStack(alignment: .leading, spacing: 6) {
            NemaraEyebrow("NOTE (OPTIONAL)")
            textField("e.g. Mom's afternoon pills", text: $note)
        }
    }

    private var promptInput: some View {
        VStack(alignment: .leading, spacing: 6) {
            NemaraEyebrow("WHAT TO DETECT")
            ZStack(alignment: .topLeading) {
                if prompt.isEmpty {
                    Text("e.g. check if my mom takes her medication between 11am and 5pm every day")
                        .font(NemaraFont.body)
                        .foregroundStyle(NemaraColor.ink3)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 14)
                }
                TextEditor(text: $prompt)
                    .font(NemaraFont.body)
                    .foregroundStyle(NemaraColor.ink)
                    .scrollContentBackground(.hidden)
                    .padding(8)
                    .tint(NemaraColor.terra)
            }
            .frame(minHeight: 92)
            .background(NemaraColor.card)
            .overlay(
                RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous)
                    .strokeBorder(NemaraColor.ink, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous))
        }
    }

    // MARK: - inferred review

    private func planRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(label)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(NemaraColor.ink3)
                .frame(width: 56, alignment: .leading)
            Text(value)
                .font(.system(size: 13))
                .foregroundStyle(NemaraColor.ink)
        }
    }

    private var inferredSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            NemaraColor.line.frame(height: 1).padding(.vertical, 2)
            NemaraEyebrow("✦ INFERRED — ADJUST ANYTHING", color: NemaraColor.terra)

            // Compiled-behavior preview (customs visibility): what the
            // detector will actually be configured to do, in the
            // caregiver's language — visible before it exists.
            if let plan {
                VStack(alignment: .leading, spacing: 8) {
                    NemaraEyebrow("WHAT THIS WILL DO")
                    planRow("Watches", plan.watches)
                    planRow("Alerts", plan.fires)
                    planRow("Checks", plan.checks)
                    if plan.listens {
                        planRow("Sound", "Also listens, not just watches")
                    }
                }
                .padding(12)
                .background(NemaraColor.cardAlt, in: RoundedRectangle(cornerRadius: 10))
            }

            // How it alerts — derived from the words. Sustained activities can
            // pick the edge (as it happens / when it's over / too long);
            // instant + absence detectors have no edge to choose.
            VStack(alignment: .leading, spacing: 8) {
                NemaraEyebrow("HOW IT ALERTS")
                if isSustained && alertTrigger != .absence {
                    typeCard(.leading, title: Detector.AlertTrigger.leading.caregiverLabel,
                             sub: Detector.AlertTrigger.leading.caregiverSub)
                    typeCard(.trailing, title: Detector.AlertTrigger.trailing.caregiverLabel,
                             sub: Detector.AlertTrigger.trailing.caregiverSub)
                    typeCard(.duration, title: Detector.AlertTrigger.duration.caregiverLabel,
                             sub: Detector.AlertTrigger.duration.caregiverSub)
                } else {
                    (Text(alertTrigger.caregiverLabel + ". ")
                     + Text(alertTrigger.caregiverSub))
                        .font(NemaraFont.bodySmall)
                        .foregroundColor(NemaraColor.ink2)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            if alertTrigger == .absence { scheduleEditor }

            // Category + icon
            VStack(alignment: .leading, spacing: 8) {
                NemaraEyebrow("CATEGORY")
                HStack(spacing: 8) {
                    catCard(.safety, "Safety", NemaraColor.terra, NemaraColor.terraSoft)
                    catCard(.routine, "Routine", NemaraColor.sky, NemaraColor.skySoft)
                }
            }
            VStack(alignment: .leading, spacing: 8) {
                NemaraEyebrow("ICON")
                Menu {
                    ForEach(iconOptions, id: \.self) { ic in
                        Button { icon = ic } label: {
                            Label(iconLabel(ic), systemImage: ic)
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: icon).foregroundStyle(NemaraColor.ink2)
                        Text(iconLabel(icon)).font(NemaraFont.body).foregroundStyle(NemaraColor.ink)
                        Spacer()
                        Image(systemName: "chevron.up.chevron.down")
                            .font(.system(size: 12)).foregroundStyle(NemaraColor.ink3)
                    }
                    .padding(.horizontal, 14).padding(.vertical, 12)
                    .background(NemaraColor.card)
                    .overlay(RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous)
                        .strokeBorder(NemaraColor.line, lineWidth: 1.5))
                    .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous))
                }
            }
        }
    }

    private var scheduleEditor: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Cadence
            HStack(spacing: 8) {
                segment("Daily", on: cadence == .daily) { cadence = .daily }
                segment("Weekly", on: cadence == .weekly) { cadence = .weekly }
            }
            if cadence == .weekly {
                VStack(alignment: .leading, spacing: 6) {
                    NemaraEyebrow("ON DAYS")
                    HStack(spacing: 6) {
                        ForEach(0..<7, id: \.self) { i in
                            Button {
                                if days.contains(i) { days.remove(i) } else { days.insert(i) }
                            } label: {
                                Text(dayLabels[i])
                                    .font(NemaraFont.bodySmallStrong)
                                    .foregroundStyle(days.contains(i) ? NemaraColor.paper : NemaraColor.ink2)
                                    .frame(width: 34, height: 34)
                                    .background(days.contains(i) ? NemaraColor.ink : NemaraColor.card)
                                    .clipShape(Circle())
                                    .overlay(Circle().strokeBorder(NemaraColor.line, lineWidth: days.contains(i) ? 0 : 1))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            // Window
            VStack(alignment: .leading, spacing: 6) {
                NemaraEyebrow("BETWEEN")
                HStack(spacing: 10) {
                    DatePicker("", selection: $windowStart, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                    Text("and").font(NemaraFont.bodySmall).foregroundStyle(NemaraColor.ink3)
                    DatePicker("", selection: $windowEnd, displayedComponents: .hourAndMinute)
                        .labelsHidden()
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                NemaraEyebrow("ALERT IF NOT SEEN BY")
                DatePicker("", selection: $deadline, displayedComponents: .hourAndMinute)
                    .labelsHidden()
            }
            if timesUncertain {
                Text("Memoria wasn't sure of the exact times — please confirm them.")
                    .font(NemaraFont.caption)
                    .foregroundStyle(NemaraColor.terra)
            }
        }
        .padding(14)
        .background(NemaraColor.paperDim)
        .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous))
    }

    // MARK: - footer

    private var footer: some View {
        VStack(spacing: 8) {
            if stage == .entry {
                NemaraButton("✦ Generate", variant: .primary, size: .lg, block: true) {
                    Task { await generate() }
                }
                .disabled(busy || prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            } else {
                NemaraButton("Create detector", variant: .primary, size: .lg, block: true) {
                    Task { await create() }
                }
                .disabled(busy)
                Button("← Edit") { stage = .entry }
                    .font(NemaraFont.bodySmall)
                    .foregroundStyle(NemaraColor.ink3)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(NemaraColor.paper)
        .overlay(NemaraColor.line.frame(height: 1), alignment: .top)
    }

    // MARK: - actions

    private func generate() async {
        let p = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !p.isEmpty else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let inf = try await env.api.inferDetector(
                InferDetectorRequest(name: trimmedName.isEmpty ? nil : trimmedName, prompt: p)
            )
            alertTrigger = inf.alertTrigger
            isSustained = inf.isSustained
            durationSeconds = inf.durationSeconds
            episodeGapSeconds = inf.episodeGapSeconds
            category = inf.category
            icon = inf.iconName
            sensitivity = inf.sensitivity
            plan = inf.plan
            let s = inf.scheduleConfig
            cadence = s?.cadence ?? .daily
            days = Set(s?.daysOfWeek ?? [])
            let ws = Self.parseHHMM(s?.windowStart)
            let we = Self.parseHHMM(s?.windowEnd)
            let dl = Self.parseHHMM(s?.deadline)
            windowStart = ws ?? Self.defaultTime(9, 0)
            windowEnd = we ?? Self.defaultTime(17, 0)
            deadline = dl ?? we ?? Self.defaultTime(17, 0)
            timesUncertain = inf.alertTrigger == .absence && (ws == nil || we == nil || dl == nil)
            stage = .review
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// schedule_config dissolution (2026-07-18): when_scope is THE
    /// windows mechanism. Scheduled shapes serialize their pickers as
    /// scope text — "MON,WED 8:00 AM - 9:00 AM" — which the backend
    /// parser reads directly (deadline ≡ window end in the unified
    /// window(hit|miss) fire rule). schedule_config is no longer sent.
    private static let dayNames = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]

    private static func formatScopeTime(_ date: Date) -> String {
        let f = DateFormatter()
        // Fixed locale: the backend grammar requires AM/PM tokens
        // regardless of the device's 24-hour setting.
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    private static func formatWhenScope(
        cadence: Detector.ScheduleConfig.Cadence,
        days: Set<Int>,
        start: Date,
        end: Date
    ) -> String {
        let window = "\(formatScopeTime(start)) - \(formatScopeTime(end))"
        guard cadence == .weekly, !days.isEmpty else { return window }
        let prefix = days.sorted().compactMap { dayNames.indices.contains($0) ? dayNames[$0] : nil }
            .joined(separator: ",")
        return prefix.isEmpty ? window : "\(prefix) \(window)"
    }

    private func create() async {
        busy = true; error = nil
        defer { busy = false }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let whenScope = alertTrigger == .absence
            ? Self.formatWhenScope(cadence: cadence, days: days,
                                   start: windowStart, end: windowEnd)
            : "ALWAYS"
        let body = CreateDetectorRequest(
            name: trimmedName.isEmpty ? "Custom detector" : trimmedName,
            customPrompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
            description: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Custom detector"
                : note.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category,
            alertTrigger: alertTrigger,
            isSustained: isSustained,
            durationSeconds: alertTrigger == .duration ? durationSeconds : nil,
            iconName: icon,
            whenScope: whenScope,
            sensitivity: sensitivity,
            scheduleConfig: nil,
            episodeGapSeconds: isSustained ? episodeGapSeconds : nil,
            isOn: false,
        )
        do {
            // Create-as-draft: the detector is created OFF; present it in the
            // detail sheet so the caregiver reviews the compiled criteria (and
            // picks rooms / refines) before turning it on (item C2).
            let created = try await env.api.createCustomDetector(forPatient: patientId, body)
            createdDetector = created
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - small components

    private func textField(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(NemaraFont.body)
            .foregroundStyle(NemaraColor.ink)
            .tint(NemaraColor.terra)
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(NemaraColor.card)
            .overlay(RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous)
                .strokeBorder(NemaraColor.ink, lineWidth: 1.5))
            .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous))
            .textInputAutocapitalization(.sentences)
            .submitLabel(.done)
            .onSubmit { Self.resignFirstResponder() }
    }

    private func typeCard(_ kind: Detector.AlertTrigger, title: String, sub: String) -> some View {
        let on = alertTrigger == kind
        return Button { alertTrigger = kind } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: on ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(on ? NemaraColor.terra : NemaraColor.ink3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(NemaraFont.bodySmallStrong).foregroundStyle(NemaraColor.ink)
                    Text(sub).font(NemaraFont.caption).foregroundStyle(NemaraColor.ink3)
                }
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 12)
            .background(on ? NemaraColor.terraSoft : NemaraColor.card)
            .overlay(RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous)
                .strokeBorder(on ? NemaraColor.terra : NemaraColor.line, lineWidth: 1.5))
            .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func catCard(_ kind: Detector.Category, _ label: String, _ tone: Color, _ soft: Color) -> some View {
        let on = category == kind
        return Button { category = kind } label: {
            HStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 4, style: .continuous).fill(tone).frame(width: 8, height: 8)
                Text(label).font(NemaraFont.bodySmallStrong).foregroundStyle(on ? tone : NemaraColor.ink)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(on ? soft : NemaraColor.card)
            .overlay(RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous)
                .strokeBorder(on ? tone : NemaraColor.line, lineWidth: 1.5))
            .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func segment(_ label: String, on: Bool, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(NemaraFont.bodySmallStrong)
                .foregroundStyle(on ? NemaraColor.ink : NemaraColor.ink3)
                .frame(maxWidth: .infinity).padding(.vertical, 10)
                .background(on ? NemaraColor.card : .clear)
                .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(2)
        .background(NemaraColor.paperDim)
        .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.sm, style: .continuous))
    }

    // MARK: - time helpers

    private static func defaultTime(_ h: Int, _ m: Int) -> Date {
        Calendar.current.date(bySettingHour: h, minute: m, second: 0, of: Date()) ?? Date()
    }
    private static func parseHHMM(_ s: String?) -> Date? {
        guard let s, s.count == 5 else { return nil }
        let parts = s.split(separator: ":")
        guard parts.count == 2, let h = Int(parts[0]), let m = Int(parts[1]) else { return nil }
        return defaultTime(h, m)
    }
    private static func formatHHMM(_ d: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: d)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }
}

#if DEBUG
#Preview {
    let env = AppEnvironment.preview()
    return AddDetectorView(patientId: env.api.patients[0].id)
        .environment(env)
}
#endif
