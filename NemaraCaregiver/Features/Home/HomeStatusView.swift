import SwiftUI

/// The dashboard-style Home briefing — works identically for 1 or N patients.
///
/// CORE RULE: never aggregate raw data — aggregate PER-PERSON verdicts.
/// Every earlier logic hole (one person's online cameras hiding another's
/// blindness, anonymous falls, streaks poisoned across people) came from
/// pooling events/cameras across patients. So: compute each person's status
/// independently, then fold by severity, naming names. One patient is just
/// a fold of one — same code path, no special modes.
///
/// Severity order: urgent (unreviewed serious moment) > blind (that person
/// has no working camera — never claim quiet while blind) > attention
/// (unreviewed moments) > quiet. Streak chips render only for a single
/// patient, where the numbers are unambiguous; multi-patient numbers live
/// on each person's own page.
struct HomeStatusView: View {
    @Environment(AppEnvironment.self) private var env

    // MARK: - Per-person status

    private enum Level: Int { case urgent = 0, blind = 1, attention = 2, quiet = 3 }

    private struct PersonStatus {
        var patient: Patient
        var name: String
        var level: Level
        var headline: String?      // person-specific detail for the fold
        var factLine: String       // name-tagged fact for the AI briefing
        var daysWithoutFall: String?
        var quietNights: Int
    }

    private static let seriousTerms = ["fall", "chok", "stroke", "heart", "seizure", "help"]

    private func isSerious(_ e: DetectionEvent) -> Bool {
        let t = e.title.lowercased()
        return Self.seriousTerms.contains { t.contains($0) }
    }

    private func humanize(_ e: DetectionEvent) -> String {
        let t = e.title
            .replacingOccurrences(of: "Possible ", with: "")
            .replacingOccurrences(of: "possible ", with: "")
            .lowercased()
        let place = e.location.isEmpty ? "" : " in the \(e.location.lowercased())"
        if t.contains("fall") { return "what looked like a fall\(place)" }
        if t.contains("chok") { return "possible choking\(place)" }
        if t.contains("wander") || t.contains("door") { return "activity near the door\(place)" }
        if t.contains("recover") { return "getting back up on their own\(place)" }
        return "\(t)\(place)"
    }

    private func status(for p: Patient) -> PersonStatus {
        let name = p.preferredName.isEmpty ? p.fullName : p.preferredName
        let events = (env.api.eventsByPatient[p.id] ?? []).sorted { $0.occurredAt > $1.occurredAt }
        let cameras = env.api.camerasByPatient[p.id] ?? []
        let now = Date()
        let recent = events.filter { $0.occurredAt > now.addingTimeInterval(-86_400) }

        // streaks — honest about the loaded window
        let oldest = events.last?.occurredAt
        var daysWithoutFall: String?
        if let oldest {
            if let f = events.first(where: { $0.title.lowercased().contains("fall") }) {
                daysWithoutFall = String(max(0, Int(now.timeIntervalSince(f.occurredAt) / 86_400)))
            } else {
                daysWithoutFall = "\(max(1, Int(now.timeIntervalSince(oldest) / 86_400)))+"
            }
        }
        var quiet = 0
        let cal = Calendar.current
        // no loaded events = no basis for ANY claim — a brand-new patient must
        // not get credited with "30 quiet nights" they were never watched for
        if oldest != nil { for back in 1...30 {
            guard let dayStart = cal.date(byAdding: .day, value: -back, to: cal.startOfDay(for: now)) else { break }
            let nightStart = dayStart.addingTimeInterval(22 * 3600 - 86_400)
            let nightEnd = dayStart.addingTimeInterval(6 * 3600)
            if events.contains(where: { $0.occurredAt >= nightStart && $0.occurredAt < nightEnd }) { break }
            quiet = back
            if let oldest, nightStart < oldest { break }
        } }

        // severity, per person
        if let s = recent.first(where: { isSerious($0) && $0.occurredAt > now.addingTimeInterval(-3 * 3600) && !$0.reviewed }) {
            return PersonStatus(patient: p, name: name, level: .urgent,
                                headline: humanize(s),
                                factLine: "\(name): NEEDS ATTENTION — \(humanize(s)) at \(s.occurredAt.formatted(date: .omitted, time: .shortened))",
                                daysWithoutFall: daysWithoutFall, quietNights: quiet)
        }
        if cameras.isEmpty {
            return PersonStatus(patient: p, name: name, level: .blind,
                                headline: "no cameras set up yet",
                                factLine: "\(name): not monitored yet — no cameras set up",
                                daysWithoutFall: daysWithoutFall, quietNights: quiet)
        }
        if !cameras.contains(where: { $0.online }) {
            return PersonStatus(patient: p, name: name, level: .blind,
                                headline: "cameras are offline",
                                factLine: "\(name): unwatched right now — cameras offline",
                                daysWithoutFall: daysWithoutFall, quietNights: quiet)
        }
        let unreviewed = recent.filter { !$0.reviewed }
        if !unreviewed.isEmpty {
            let first = unreviewed.first!
            return PersonStatus(patient: p, name: name, level: .attention,
                                headline: "\(unreviewed.count) unreviewed moment\(unreviewed.count == 1 ? "" : "s")",
                                factLine: "\(name): \(humanize(first)) — unreviewed",
                                daysWithoutFall: daysWithoutFall, quietNights: quiet)
        }
        return PersonStatus(patient: p, name: name, level: .quiet,
                            headline: nil,
                            factLine: "\(name): quiet\(quiet > 0 ? ", \(quiet) quiet nights in a row" : "")",
                            daysWithoutFall: daysWithoutFall, quietNights: quiet)
    }

    private var statuses: [PersonStatus] {
        env.api.patients.map(status(for:)).sorted { $0.level.rawValue < $1.level.rawValue }
    }

    // MARK: - The fold: one honest verdict across everyone

    private struct Verdict { var level: Level; var line: String; var sub: String }

    private func names(_ list: [PersonStatus]) -> String {
        list.map(\.name).joined(separator: " and ")
    }

    private var verdict: Verdict {
        let all = statuses
        guard !all.isEmpty else { return Verdict(level: .quiet, line: "Welcome", sub: "add a patient to get started") }
        let urgent = all.filter { $0.level == .urgent }
        let blind = all.filter { $0.level == .blind }
        let attention = all.filter { $0.level == .attention }
        let single = all.count == 1

        if !urgent.isEmpty {
            let u = urgent[0]
            return Verdict(level: .urgent,
                           line: single ? "Something needs your attention" : "Something needs your attention — \(names(urgent))",
                           sub: "We noticed \(u.headline ?? "a serious moment") — open \(single ? "the moment" : names(urgent)) to review it")
        }
        if !blind.isEmpty {
            if blind.count == all.count {
                return Verdict(level: .blind,
                               line: single ? "We can’t see \(blind[0].name) right now" : "No one is being watched right now",
                               sub: "")
            }
            // partial blindness must NEVER hide behind someone else's working cameras
            return Verdict(level: .blind,
                           line: "We can’t see \(names(blind)) right now",
                           sub: attention.isEmpty && urgent.isEmpty ? "Everyone else looks fine" : "")
        }
        if !attention.isEmpty {
            let n = attention.count
            return Verdict(level: .attention,
                           line: single ? "\(n == 1 ? "One thing" : "\(n) things") to look at" : "Something to look at — \(names(attention))",
                           sub: "\(n == 1 && single ? "A moment" : "Moments") from the last day \(n == 1 && single ? "hasn’t" : "haven’t") been reviewed — nothing urgent")
        }
        return Verdict(level: .quiet,
                       line: "All quiet for \(single ? all[0].name : "everyone")",
                       sub: "nothing unusual in the last day")
    }

    // MARK: - Briefing (template instantly, AI prose when the endpoint answers)

    @State private var briefing: String?

    private var briefingName: String {
        statuses.count == 1 ? statuses[0].name : "everyone"
    }

    private var templateBriefing: String {
        let all = statuses
        guard !all.isEmpty else { return "" }
        if all.count == 1 {
            let s = all[0]
            var parts: [String] = []
            if let d = s.daysWithoutFall { parts.append("it’s been \(d) days without a fall") }
            if s.quietNights > 0 { parts.append("\(s.quietNights) quiet night\(s.quietNights == 1 ? "" : "s") in a row") }
            let lead = s.level == .quiet ? "**\(s.name)** has had a calm stretch" : "**\(s.name)** has \(s.headline ?? "something to review")"
            return parts.isEmpty ? "\(lead)." : "\(lead) — \(parts.joined(separator: ", "))."
        }
        let calm = all.filter { $0.level == .quiet }.map(\.name)
        let busy = all.filter { $0.level != .quiet }
        var bits: [String] = []
        if !calm.isEmpty { bits.append("\(calm.map { "**\($0)**" }.joined(separator: " and ")) \(calm.count == 1 ? "has" : "have") had a calm day") }
        for b in busy { bits.append("**\(b.name)** has \(b.headline ?? "something to review")") }
        return bits.joined(separator: ". ") + "."
    }

    private func fetchBriefing() async {
        var facts: [String: String] = [:]
        for s in statuses { facts[s.name] = s.factLine }
        if let text = try? await env.api.homeBriefing(name: briefingName, facts: facts), !text.isEmpty {
            withAnimation(.easeOut(duration: 0.3)) { briefing = text }
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            verdictCard
            if !statuses.isEmpty {
                Text(Self.md(briefing ?? templateBriefing))
                    .font(.system(size: 17))
                    .foregroundStyle(NemaraColor.ink2)
                    .lineSpacing(5)
                    .padding(.horizontal, 2)
                    .task { await fetchBriefing() }
            }
            // streak chips ONLY when the numbers are unambiguous (one person);
            // multi-patient numbers belong on each person's own page
            if statuses.count == 1 {
                let s = statuses[0]
                HStack(spacing: 10) {
                    if let d = s.daysWithoutFall { streakChip(d, d == "1" ? "day since a fall" : "days without a fall") }
                    streakChip(String(s.quietNights), s.quietNights == 1 ? "quiet night in a row" : "quiet nights in a row")
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    private var verdictCard: some View {
        let v = verdict
        let (dot, bg): (Color, Color) = {
            switch v.level {
            case .quiet: return (NemaraColor.success, NemaraColor.success.opacity(0.12))
            case .attention, .blind: return (NemaraColor.warning, NemaraColor.warning.opacity(0.12))
            case .urgent: return (NemaraColor.danger, NemaraColor.terraSoft)
            }
        }()
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Circle().fill(dot).frame(width: 13, height: 13)
                Text(v.line)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundStyle(NemaraColor.ink)
            }
            if !v.sub.isEmpty { Text(Self.md(v.sub))
                .font(.system(size: 15))
                .foregroundStyle(NemaraColor.ink3)
                .padding(.leading, 23) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(bg, in: RoundedRectangle(cornerRadius: 22))
    }

    /// Inline-markdown render; a failed parse falls back to STRIPPED text —
    /// raw asterisks must never reach a caregiver's screen.
    static func md(_ s: String) -> AttributedString {
        if let a = try? AttributedString(
            markdown: s,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        ) { return a }
        return AttributedString(s.replacingOccurrences(of: "**", with: ""))
    }

    private func streakChip(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(value)
                .font(.system(size: 27, weight: .semibold, design: .serif))
                .foregroundStyle(NemaraColor.ink)
            Text(label)
                .font(.system(size: 12.5))
                .foregroundStyle(NemaraColor.ink3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(NemaraColor.card, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(NemaraColor.line.opacity(0.6)))
    }
}
