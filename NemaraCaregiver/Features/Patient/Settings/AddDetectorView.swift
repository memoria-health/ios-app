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
    private let dayLabels = ["M", "T", "W", "T", "F", "S", "S"] // 0=Mon..6=Sun

    @State private var stage: Stage = .entry
    @State private var busy = false
    @State private var error: String?

    // Entry
    @State private var name = ""
    @State private var note = ""
    @State private var prompt = ""

    // Inferred + editable
    @State private var shape: Detector.Shape = .pointInTime
    @State private var category: Detector.Category = .safety
    @State private var icon = "eye"
    @State private var sensitivity: Detector.Sensitivity = .standard
    @State private var cadence: Detector.ScheduleConfig.Cadence = .daily
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
                footer
            }
            .background(NemaraColor.paper)
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
            Text("What should Nemara watch for?")
                .font(NemaraFont.title1)
                .kerning(-0.7)
                .foregroundStyle(NemaraColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            Text("Describe it in plain words. Nemara figures out the rest — including whether it's a live alert or a daily/weekly check.")
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

    private var inferredSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            NemaraColor.line.frame(height: 1).padding(.vertical, 2)
            NemaraEyebrow("✦ INFERRED — ADJUST ANYTHING", color: NemaraColor.terra)

            // Type
            VStack(alignment: .leading, spacing: 8) {
                NemaraEyebrow("TYPE")
                typeCard(isScheduled: true, title: "Scheduled check",
                         sub: "alerts if it DOESN'T happen in a window")
                typeCard(isScheduled: false, title: "Live detection",
                         sub: "fires the moment it's seen")
            }

            if shape == .scheduled { scheduleEditor }

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
                            Label(ic, systemImage: ic)
                        }
                    }
                } label: {
                    HStack {
                        Image(systemName: icon).foregroundStyle(NemaraColor.ink2)
                        Text(icon).font(NemaraFont.body).foregroundStyle(NemaraColor.ink)
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
                Text("Nemara wasn't sure of the exact times — please confirm them.")
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
            shape = inf.shape == .state ? .pointInTime : inf.shape
            category = inf.category
            icon = inf.iconName
            sensitivity = inf.sensitivity
            let s = inf.scheduleConfig
            cadence = s?.cadence ?? .daily
            days = Set(s?.daysOfWeek ?? [])
            let ws = Self.parseHHMM(s?.windowStart)
            let we = Self.parseHHMM(s?.windowEnd)
            let dl = Self.parseHHMM(s?.deadline)
            windowStart = ws ?? Self.defaultTime(9, 0)
            windowEnd = we ?? Self.defaultTime(17, 0)
            deadline = dl ?? we ?? Self.defaultTime(17, 0)
            timesUncertain = inf.shape == .scheduled && (ws == nil || we == nil || dl == nil)
            stage = .review
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func create() async {
        busy = true; error = nil
        defer { busy = false }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let scheduleConfig: Detector.ScheduleConfig? = shape == .scheduled
            ? Detector.ScheduleConfig(
                cadence: cadence,
                daysOfWeek: cadence == .weekly ? days.sorted() : nil,
                windowStart: Self.formatHHMM(windowStart),
                windowEnd: Self.formatHHMM(windowEnd),
                deadline: Self.formatHHMM(deadline),
              )
            : nil
        let body = CreateDetectorRequest(
            name: trimmedName.isEmpty ? "Custom detector" : trimmedName,
            customPrompt: prompt.trimmingCharacters(in: .whitespacesAndNewlines),
            description: note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "Custom detector"
                : note.trimmingCharacters(in: .whitespacesAndNewlines),
            category: category,
            shape: shape,
            iconName: icon,
            sensitivity: sensitivity,
            scheduleConfig: scheduleConfig,
        )
        do {
            _ = try await env.api.createCustomDetector(forPatient: patientId, body)
            dismiss()
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
    }

    private func typeCard(isScheduled: Bool, title: String, sub: String) -> some View {
        let on = (shape == .scheduled) == isScheduled
        return Button { shape = isScheduled ? .scheduled : .pointInTime } label: {
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
