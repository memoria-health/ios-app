import Foundation
import Supabase

/// Compile-time configuration + master kill switch for UI analytics.
///
/// Flip `enabled` to `false` to disable the entire system instantly — every
/// `log*` call and the flush worker become no-ops with one line changed.
enum AnalyticsConfig {
    /// Master on/off. When `false`, nothing is buffered, persisted, or sent.
    static let enabled = true
    /// How often the background worker drains the buffer to Supabase.
    static let flushInterval: TimeInterval = 3600          // hourly
    /// Persist the buffer to disk after this many new events (crash safety).
    static let persistEveryN = 25
    /// Hard cap on the in-memory/on-disk buffer. Oldest events are dropped
    /// past this so a long offline stretch can't grow memory unbounded.
    static let maxBufferedEvents = 5000
    /// Rows per insert request when flushing.
    static let batchSize = 200
}

/// UI-interaction analytics for the caregiver app.
///
/// **Design contract (do not break): zero logic changes.** `log*` is a
/// synchronous, non-throwing, side-effect-only buffer append that runs
/// *alongside* the existing UI action — it never wraps, blocks, throws, or
/// awaits. The ONLY async is one isolated, failure-safe background flush. If
/// analytics breaks entirely, the app behaves identically; you just get no
/// data.
///
/// A `@MainActor` singleton because instrumentation is sprinkled across leaf
/// views (every `NemaraButton`, `NemaraToggle`, screen) and threading a
/// dependency through all of them isn't worth it. UI events are all on the
/// main thread, so the buffer needs no locking.
@MainActor
final class Analytics {
    static let shared = Analytics()

    // MARK: Event model

    /// One buffered event. Field names match the `ui_events` columns exactly
    /// (PostgREST maps JSON keys → columns), so a row is inserted by encoding
    /// this struct directly. `received_at` is omitted — the DB defaults it.
    struct Event: Codable, Sendable {
        let id: String              // client-generated UUID → idempotent upsert
        let caregiver_id: String?   // stamped at log time; nil before sign-in
        let session_id: String
        let seq: Int
        let event_type: String      // button | screen | toggle | lifecycle
        let name: String
        let screen: String?
        let occurred_at: String     // ISO8601, ms precision (client clock)
        let app_build: String?
        let os_version: String?
        let device_model: String?
        let metadata: [String: String]?
    }

    // MARK: Session state

    /// New identity per app launch → groups one session's events.
    private let sessionID = UUID().uuidString
    /// Monotonic per-session counter — exact ordering even on timestamp ties.
    private var seq = 0
    /// The screen the user is currently on, attached to button/toggle events.
    private var currentScreen: String?

    // MARK: Buffer

    private var buffer: [Event] = []
    private var eventsSincePersist = 0

    // MARK: Injected dependencies (set in `configure`)

    private var client: SupabaseClient?
    private var caregiverIDProvider: (() -> UUID?)?
    private var flushTask: Task<Void, Never>?
    private var isFlushing = false
    private var didConfigure = false

    // MARK: Device/app context (captured once)

    private let appBuild: String?
    private let osVersion: String?
    private let deviceModel: String?

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private init() {
        let info = Bundle.main.infoDictionary
        if let short = info?["CFBundleShortVersionString"] as? String,
           let build = info?["CFBundleVersion"] as? String {
            appBuild = "\(short) (\(build))"
        } else {
            appBuild = info?["CFBundleShortVersionString"] as? String
        }
        let v = ProcessInfo.processInfo.operatingSystemVersion
        osVersion = "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
        deviceModel = Analytics.deviceModelIdentifier()
    }

    // MARK: - Configuration

    /// Wire in the Supabase client + a way to read the current caregiver id,
    /// load any events persisted from a previous session, and start the
    /// background flush worker. Called once from `AppEnvironment.live()`.
    /// Idempotent — safe if called again (restarts the worker).
    func configure(client: SupabaseClient, caregiverIDProvider: @escaping () -> UUID?) {
        guard AnalyticsConfig.enabled else { return }
        self.client = client
        self.caregiverIDProvider = caregiverIDProvider

        if !didConfigure {
            didConfigure = true
            loadPersisted()
        }

        flushTask?.cancel()
        flushTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(AnalyticsConfig.flushInterval * 1_000_000_000))
                if Task.isCancelled { break }
                await self?.flush()
            }
        }
        // Drain anything left over from the previous session shortly after launch.
        Task { [weak self] in await self?.flush() }
    }

    // MARK: - Logging (synchronous, non-throwing — the safety core)

    /// Record a button tap. `name` is the explicit track label when set, else
    /// the button title. Screen context is attached automatically.
    func logButton(_ name: String) {
        append(type: "button", name: name, screen: currentScreen, metadata: nil)
    }

    /// Record a toggle flip with its new on/off value.
    func logToggle(_ name: String, isOn: Bool) {
        append(type: "toggle", name: name, screen: currentScreen,
               metadata: ["value": isOn ? "on" : "off"])
    }

    /// Record (and become) the current screen. Drives the screen-flow funnel
    /// and the screen context stamped onto subsequent button/toggle events.
    func logScreen(_ name: String) {
        guard AnalyticsConfig.enabled else { return }
        currentScreen = name
        append(type: "screen", name: name, screen: name, metadata: nil)
    }

    /// Record an app-lifecycle transition (`app_launch` / `app_foreground` /
    /// `app_background`). Same zero-cost append as a button.
    func logLifecycle(_ name: String) {
        append(type: "lifecycle", name: name, screen: currentScreen, metadata: nil)
    }

    private func append(type: String, name: String, screen: String?, metadata: [String: String]?) {
        guard AnalyticsConfig.enabled else { return }
        let event = Event(
            id: UUID().uuidString,
            caregiver_id: caregiverIDProvider?()?.uuidString,
            session_id: sessionID,
            seq: seq,
            event_type: type,
            name: name,
            screen: screen,
            occurred_at: Analytics.iso.string(from: Date()),
            app_build: appBuild,
            os_version: osVersion,
            device_model: deviceModel,
            metadata: metadata,
        )
        seq += 1
        buffer.append(event)
        // Bound memory: drop oldest if a long offline stretch overflows.
        if buffer.count > AnalyticsConfig.maxBufferedEvents {
            buffer.removeFirst(buffer.count - AnalyticsConfig.maxBufferedEvents)
        }
        eventsSincePersist += 1
        if eventsSincePersist >= AnalyticsConfig.persistEveryN {
            persist()
        }
    }

    // MARK: - Lifecycle hook

    /// Called on app background: snapshot to disk + kick a flush. Both are
    /// fire-and-forget and failure-safe.
    func persistAndFlush() {
        guard AnalyticsConfig.enabled else { return }
        persist()
        Task { [weak self] in await self?.flush() }
    }

    // MARK: - Persistence (crash safety; survives app kill)

    /// Encode the buffer on the main actor (cheap) and write it off-main
    /// (atomic). Wrapped so a failure is silently ignored.
    private func persist() {
        eventsSincePersist = 0
        guard let url = Analytics.fileURL else { return }
        guard let data = try? JSONEncoder().encode(buffer) else { return }
        Task.detached(priority: .utility) {
            try? data.write(to: url, options: .atomic)
        }
    }

    /// Load events persisted by a previous session so a kill/crash doesn't
    /// lose them — they flush on next launch.
    private func loadPersisted() {
        guard let url = Analytics.fileURL,
              let data = try? Data(contentsOf: url),
              let saved = try? JSONDecoder().decode([Event].self, from: data)
        else { return }
        buffer = saved + buffer
        if buffer.count > AnalyticsConfig.maxBufferedEvents {
            buffer.removeFirst(buffer.count - AnalyticsConfig.maxBufferedEvents)
        }
    }

    // MARK: - Flush (the only async — isolated + failure-safe)

    /// Drain the current caregiver's buffered events to Supabase in batches.
    /// Only events attributed to the currently-authed caregiver are sent
    /// (the only ones RLS will accept); everything else stays buffered. Any
    /// error aborts the flush and keeps the events for next time. Never
    /// throws, never touches UI logic.
    private func flush() async {
        guard AnalyticsConfig.enabled, !isFlushing, let client else { return }
        guard let currentID = caregiverIDProvider?()?.uuidString else { return }
        isFlushing = true
        defer { isFlushing = false }

        // Only the authed user's events are insertable under RLS.
        let sendable = buffer.filter { $0.caregiver_id == currentID }
        guard !sendable.isEmpty else { return }

        var sentIDs = Set<String>()
        for chunk in sendable.chunked(into: AnalyticsConfig.batchSize) {
            do {
                // Upsert + ignoreDuplicates makes a retry after a dropped
                // response idempotent (client `id` is the conflict key) instead
                // of failing the whole batch forever on a PK collision.
                try await client
                    .from("ui_events")
                    .upsert(chunk, onConflict: "id", ignoreDuplicates: true)
                    .execute()
                sentIDs.formUnion(chunk.map(\.id))
            } catch {
                // Stop on first failure; keep everything not yet confirmed sent.
                break
            }
        }

        guard !sentIDs.isEmpty else { return }
        buffer.removeAll { sentIDs.contains($0.id) }
        persist()
    }

    // MARK: - Helpers

    private static var fileURL: URL? {
        let fm = FileManager.default
        guard let dir = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first else { return nil }
        if !fm.fileExists(atPath: dir.path) {
            try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        return dir.appendingPathComponent("ui_events_buffer.json")
    }

    /// Raw hardware identifier (e.g. "iPhone15,3"). Foundation-only; avoids a
    /// UIKit import for one string.
    private static func deviceModelIdentifier() -> String {
        var sysinfo = utsname()
        uname(&sysinfo)
        let machine = withUnsafePointer(to: &sysinfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
        return machine
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
