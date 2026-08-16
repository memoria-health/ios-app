import SwiftUI

/// The patient Home tab — the Daily Journal.
///
/// One page per day (design: nemara-backend
/// docs/plans/2026-08-16-daily-journal.md). Lands on "So far today",
/// chevrons or a swipe walk back in time. Every line is computed
/// server-side; this view renders and never composes. Alerts stay on
/// the roster and the Events tab — the Review chip deep-links there.
struct PatientHomeView: View {
    @Environment(AppEnvironment.self) private var env

    let patientId: UUID

    /// 0 = today, 1 = yesterday, … capped at 30 days back for v1.
    @State private var daysBack = 0
    @State private var days: [String: JournalDay] = [:]
    @State private var failedDate: String?
    /// Bumped on significant-time-change so the day pager rolls over.
    @State private var dayTick = 0

    private static let maxBack = 30

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: NemaraSpacing.sm) {
                pager
                content
            }
            .padding(.horizontal, 14)
            .padding(.bottom, NemaraSpacing.lg)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .refreshable { await load(force: true) }
        .task(id: "\(daysBack)-\(dayTick)") { await load() }
        // Midnight/timezone rollover: without this, an app left open on
        // "So far today" keeps showing yesterday labeled as today.
        .onReceive(NotificationCenter.default.publisher(
            for: UIApplication.significantTimeChangeNotification)) { _ in
            dayTick += 1
        }
        // Day paging is chevron-only (Aryaman, Aug 16): even a
        // dominance-gated swipe competed with vertical scrolling.
    }

    // MARK: - Day pager

    private var date: Date {
        Calendar.current.date(byAdding: .day, value: -daysBack, to: Date())!
    }

    private static let dayFormatter: DateFormatter = {
        // POSIX locale + Gregorian: a device set to the Buddhist
        // calendar would otherwise emit year 2569 and query a day 543
        // years in the future.
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    private var dateString: String {
        Self.dayFormatter.string(from: date)
    }

    private var eyebrow: String {
        switch daysBack {
        case 0: return "So far today"
        case 1: return "Yesterday"
        default: return date.formatted(.dateTime.weekday(.wide))
        }
    }

    private var pager: some View {
        HStack {
            chevron("chevron.left", enabled: daysBack < Self.maxBack) {
                daysBack += 1
            }
            Spacer()
            VStack(spacing: 2) {
                Text(eyebrow.uppercased())
                    .font(NemaraFont.captionStrong)
                    .foregroundStyle(NemaraColor.terra)
                    .kerning(1.4)
                Text(date.formatted(.dateTime.month(.wide).day()))
                    .font(NemaraFont.largeTitle)
                    .foregroundStyle(NemaraColor.ink)
            }
            Spacer()
            chevron("chevron.right", enabled: daysBack > 0) {
                daysBack -= 1
            }
        }
        .padding(.top, 4)
    }

    private func chevron(_ symbol: String, enabled: Bool,
                         action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(NemaraColor.ink2)
                .frame(width: 38, height: 38)
                .background(NemaraColor.card, in: Circle())
                .overlay(Circle().strokeBorder(NemaraColor.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.3)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if let day = days[dateString] {
            if day.sections.isEmpty {
                DashboardEmptyStateView(hasDetectors: true)
            } else {
                JournalDayView(day: day) { eventId in
                    // The shell watches focusEventId and jumps to Events.
                    env.deepLink.focusEventId = eventId
                }
            }
        } else if failedDate == dateString {
            Button {
                failedDate = nil
                Task { await load() }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.clockwise")
                    Text("Couldn't load this day. Tap to retry")
                }
                .font(NemaraFont.bodySemibold)
                .foregroundStyle(NemaraColor.ink2)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(NemaraColor.card, in: Capsule())
            }
            .buttonStyle(.plain)
            .frame(maxWidth: .infinity, minHeight: 200)
        } else {
            ProgressView()
                .frame(maxWidth: .infinity, minHeight: 200)
        }
    }

    private func load(force: Bool = false) async {
        let key = dateString
        // Completed days never change; today refetches on every visit.
        if !force, let cached = days[key], !cached.partial { return }
        do {
            days[key] = try await env.api.journal(patientId: patientId,
                                                  date: key)
            failedDate = nil
        } catch is CancellationError {
            // Pull-to-refresh dismissing cancels the request — that is
            // not a failure, and flashing the retry face for it made
            // every other pull look broken.
        } catch let e as URLError where e.code == .cancelled {
        } catch {
            if days[key] == nil { failedDate = key }
        }
    }
}

/// Centered middle-of-page empty state — an icon mark with a few words
/// under it, no card.
struct DashboardEmptyStateView: View {
    let hasDetectors: Bool

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(NemaraColor.card)
                    .frame(width: 92, height: 92)
                Circle()
                    .strokeBorder(NemaraColor.line, lineWidth: 1)
                    .frame(width: 92, height: 92)
                Image(systemName: "book.closed")
                    .font(.system(size: 32, weight: .light))
                    .foregroundStyle(NemaraColor.ink3)
            }
            VStack(spacing: 5) {
                Text("Nothing to see yet")
                    .font(NemaraFont.title3)
                    .foregroundStyle(NemaraColor.ink)
                Text(hasDetectors
                     ? "Turn on a detector and its day appears here."
                     : "Add a detector and its day appears here.")
                    .font(NemaraFont.bodySmall)
                    .foregroundStyle(NemaraColor.ink3)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 420)
    }
}
