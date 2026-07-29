import SwiftUI

/// The dashboard's family Home, in the app — answers before navigation.
/// Sits at the top of the Home tab above the roster: one glanceable
/// verdict, streaks, and a plain-language feed, all computed CLIENT-SIDE
/// from data `bootstrap()` already loads (no backend changes).
///
/// Design rules (mirrors the web Home):
///  - three status colors ever: success (fine) / warning (look) / danger (now)
///  - NEVER say "all quiet" while zero cameras are online — no false
///    reassurance while blind
///  - events render as calm sentences, not enum-flavored titles
struct HomeStatusView: View {
    @Environment(AppEnvironment.self) private var env

    private var allEvents: [DetectionEvent] {
        env.api.eventsByPatient.values.flatMap { $0 }.sorted { $0.occurredAt > $1.occurredAt }
    }
    private var allCameras: [Camera] {
        env.api.camerasByPatient.values.flatMap { $0 }
    }

    // MARK: - Verdict

    private enum Level { case ok, attention, urgent }

    private struct Verdict {
        var level: Level
        var line: String
        var sub: String
    }

    private static let seriousTerms = ["fall", "chok", "stroke", "heart", "seizure", "help"]

    private func isSerious(_ e: DetectionEvent) -> Bool {
        let t = e.title.lowercased()
        return Self.seriousTerms.contains { t.contains($0) }
    }

    private var verdict: Verdict {
        let now = Date()
        let dayAgo = now.addingTimeInterval(-86_400)
        let recent = allEvents.filter { $0.occurredAt > dayAgo }
        let names = env.api.patients.map { $0.preferredName.isEmpty ? $0.fullName : $0.preferredName }
        let who = names.count == 1 ? names[0] : "everyone"

        if let s = recent.first(where: { isSerious($0) && $0.occurredAt > now.addingTimeInterval(-3 * 3600) && !$0.reviewed }) {
            return Verdict(level: .urgent,
                           line: "Something needs your attention",
                           sub: "\(humanize(s)) — tap the moment below to review it")
        }
        if !allCameras.isEmpty && !allCameras.contains(where: { $0.online }) {
            // never claim quiet while blind
            return Verdict(level: .attention,
                           line: "The cameras are offline",
                           sub: "We can’t check in right now — a camera may be unplugged or the internet may be down")
        }
        let unreviewed = recent.filter { !$0.reviewed }
        if !unreviewed.isEmpty {
            let n = unreviewed.count
            // facilities need the WHO immediately — name the people involved
            let whoNames: String = {
                guard env.api.patients.count > 1 else { return "" }
                let ids = Set(unreviewed.map(\.patientId))
                let list = env.api.patients.filter { ids.contains($0.id) }
                    .map { $0.preferredName.isEmpty ? $0.fullName : $0.preferredName }
                return list.isEmpty ? "" : " — \(list.joined(separator: " and "))"
            }()
            return Verdict(level: .attention,
                           line: "\(n == 1 ? "One thing" : "\(n) things") to look at\(whoNames)",
                           sub: "\(n == 1 ? "A moment" : "Some moments") from the last day \(n == 1 ? "hasn’t" : "haven’t") been reviewed — nothing urgent")
        }
        return Verdict(level: .ok,
                       line: "All quiet for \(who)",
                       sub: recent.isEmpty ? "nothing unusual in the last day" : "everything from the last day has been reviewed")
    }

    // MARK: - Streaks (from the loaded event window — honest about its horizon)

    private var oldestLoaded: Date? { allEvents.last?.occurredAt }

    private var daysSinceLastFall: (value: String, label: String)? {
        guard oldestLoaded != nil else { return nil }
        let lastFall = allEvents.first { $0.title.lowercased().contains("fall") }
        if let f = lastFall {
            let d = max(0, Int(Date().timeIntervalSince(f.occurredAt) / 86_400))
            return (String(d), d == 1 ? "day since a fall" : "days without a fall")
        }
        let horizon = max(1, Int(Date().timeIntervalSince(oldestLoaded!) / 86_400))
        return ("\(horizon)+", "days without a fall")
    }

    private var quietNights: (value: String, label: String) {
        var nights = 0
        let cal = Calendar.current
        for back in 1...30 {
            guard let dayStart = cal.date(byAdding: .day, value: -back, to: cal.startOfDay(for: Date())) else { break }
            let nightStart = dayStart.addingTimeInterval(22 * 3600 - 86_400) // 22:00 the evening before
            let nightEnd = dayStart.addingTimeInterval(6 * 3600)             // 06:00 that morning
            let had = allEvents.contains { $0.occurredAt >= nightStart && $0.occurredAt < nightEnd }
            if had { break }
            if let oldest = oldestLoaded, nightStart < oldest { nights = back; break }
            nights = back
        }
        return (String(nights), nights == 1 ? "quiet night in a row" : "quiet nights in a row")
    }

    // MARK: - Feed language

    private func humanize(_ e: DetectionEvent) -> String {
        let t = e.title
            .replacingOccurrences(of: "Possible ", with: "")
            .replacingOccurrences(of: "possible ", with: "")
            .lowercased()
        let place = e.location.isEmpty ? "" : " in the \(e.location.lowercased())"
        if t.contains("fall") { return "We noticed what looked like a fall\(place)" }
        if t.contains("chok") { return "We noticed possible choking\(place)" }
        if t.contains("wander") || t.contains("door") { return "Activity near the door\(place)" }
        if t.contains("recover") { return "They got back up on their own\(place)" }
        return "We noticed \(t)\(place)"
    }

    private var feed: [DetectionEvent] { Array(allEvents.prefix(8)) }

    // MARK: - Body

    @State private var briefing: String?

    private var briefingName: String {
        let names = env.api.patients.map { $0.preferredName.isEmpty ? $0.fullName : $0.preferredName }
        return names.count == 1 ? names[0] : "everyone"
    }

    private var templateBriefing: String {
        var parts: [String] = []
        if let f = daysSinceLastFall { parts.append("it’s been \(f.value) \(f.label)") }
        let q = quietNights
        if let n = Int(q.value), n > 0 { parts.append("\(q.value) \(q.label)") }
        let lead = allEvents.first { $0.occurredAt > Date().addingTimeInterval(-86_400) } == nil
            ? "\(briefingName == "everyone" ? "Everyone has" : "\(briefingName) has") had a quiet day so far"
            : "\(briefingName == "everyone" ? "Everyone is" : "\(briefingName) is") going about the day"
        return parts.isEmpty ? "\(lead)." : "\(lead) — \(parts.joined(separator: ", "))."
    }

    private func fetchBriefing() async {
        var facts: [String: String] = ["camerasWatching": camerasLine]
        if let f = daysSinceLastFall { facts["daysSinceLastFall"] = f.value }
        facts["quietNightsInARow"] = quietNights.value
        for (i, e) in feed.prefix(4).enumerated() {
            facts["moment\(i + 1)"] = "\(e.occurredAt.formatted(date: .abbreviated, time: .shortened)): \(humanize(e))"
        }
        if let text = try? await env.api.homeBriefing(name: briefingName, facts: facts), !text.isEmpty {
            withAnimation(.easeOut(duration: 0.3)) { briefing = text }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            verdictCard
            Text(briefing ?? templateBriefing)
                .font(.system(size: 16, weight: .regular, design: .serif))
                .foregroundStyle(NemaraColor.ink2)
                .lineSpacing(3)
                .padding(.horizontal, 2)
                .task { await fetchBriefing() }
            HStack(spacing: 10) {
                if let f = daysSinceLastFall { streakChip(f.value, f.label) }
                let q = quietNights
                streakChip(q.value, q.label)
            }
            if !feed.isEmpty { feedSection }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    private var verdictCard: some View {
        let v = verdict
        let (dot, bg): (Color, Color) = {
            switch v.level {
            case .ok: return (NemaraColor.success, NemaraColor.success.opacity(0.12))
            case .attention: return (NemaraColor.warning, NemaraColor.warning.opacity(0.12))
            case .urgent: return (NemaraColor.danger, NemaraColor.terraSoft)
            }
        }()
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                Circle().fill(dot).frame(width: 13, height: 13)
                Text(v.line)
                    .font(.system(size: 21, weight: .semibold, design: .serif))
                    .foregroundStyle(NemaraColor.ink)
            }
            Text(v.sub)
                .font(.system(size: 14.5))
                .foregroundStyle(NemaraColor.ink3)
                .padding(.leading, 23)
            Text(camerasLine)
                .font(.system(size: 12.5))
                .foregroundStyle(NemaraColor.ink4)
                .padding(.leading, 23)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(bg, in: RoundedRectangle(cornerRadius: 22))
    }

    private var camerasLine: String {
        let on = allCameras.filter { $0.online }.count
        let total = allCameras.count
        guard total > 0 else { return "no cameras set up yet" }
        return "\(on) of \(total) camera\(total == 1 ? "" : "s") watching"
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

    private var feedSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("RECENT MOMENTS")
                .font(.system(size: 11, weight: .semibold))
                .kerning(0.8)
                .foregroundStyle(NemaraColor.ink4)
                .padding(.top, 4)
            ForEach(feed) { e in
                Button { env.deepLink.openPatient(e.patientId) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(e.occurredAt.formatted(date: .abbreviated, time: .shortened))
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(NemaraColor.ink4)
                            .frame(width: 92, alignment: .leading)
                        Text(humanize(e))
                            .font(.system(size: 14.5))
                            .foregroundStyle(NemaraColor.ink2)
                            .multilineTextAlignment(.leading)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .background(
                        isSerious(e) ? NemaraColor.terraSoft.opacity(0.55) : NemaraColor.card,
                        in: RoundedRectangle(cornerRadius: 14)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }
}
