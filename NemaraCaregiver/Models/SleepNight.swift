import Foundation

/// One night, as the backend folded it (`sleep_nights`).
///
/// Every field except `night` is optional because a night can be
/// legitimately incomplete: the summariser refuses to invent a wake time
/// for someone still asleep, and refuses to open a night at all if it
/// could not establish who got into the bed. `flags` says which of those
/// happened — the card reads it rather than guessing from nulls.
struct SleepNight: Codable, Hashable, Identifiable {
    /// "YYYY-MM-DD" — the EVENING's date, so last night's record is
    /// filed under yesterday.
    let night: String
    let bedtime: Date?
    let sleepOnset: Date?
    let wakeTime: Date?
    let durationMinutes: Int?
    let disturbances: Int
    /// Wake-up WINDOWS, not a bare count: a caregiver can check a window
    /// against what the person remembers, and cannot check a number.
    let outOfBedEvents: [SleepWindow]
    let flags: [String]

    var id: String { night }

    enum CodingKeys: String, CodingKey {
        case night, bedtime, disturbances, flags
        case sleepOnset = "sleep_onset"
        case wakeTime = "wake_time"
        case durationMinutes = "duration_minutes"
        case outOfBedEvents = "out_of_bed_events"
    }

    /// A night with a real measured sleep period. Anything else is shown
    /// as "no sleep recorded" rather than as zeroes, because a zero here
    /// reads as "they did not sleep" when it means "we could not tell".
    var isComplete: Bool { sleepOnset != nil && wakeTime != nil }

    /// Why an incomplete night is incomplete, in the caregiver's words.
    /// nil when the night is complete.
    var incompleteReason: String? {
        if isComplete { return nil }
        if flags.contains("no_confirmed_bed_entry") {
            return "Couldn't confirm who got into bed"
        }
        if flags.contains("wake_unobserved") { return "Still asleep" }
        if flags.contains("incomplete_night") { return "Night still in progress" }
        if flags.contains("no_sleep_onset") { return "No settled sleep seen" }
        if flags.contains("no_ticks") { return "Nothing recorded" }
        return "No sleep recorded"
    }

    /// "6h 12m", or nil when there is no measured duration.
    var durationText: String? {
        guard let m = durationMinutes, m > 0 else { return nil }
        return m < 60 ? "\(m)m" : "\(m / 60)h \(m % 60)m"
    }
}

/// A wake-up during the night.
///
/// The keys are `from`/`to`, which is what `sleep_summary` writes. Rows
/// computed before 2026-08-03 used `start`/`end`; both are accepted so a
/// fortnight of history does not decode as an unbroken night.
struct SleepWindow: Codable, Hashable {
    let start: Date
    let end: Date?
    let durationMinutes: Int?

    private enum CodingKeys: String, CodingKey {
        case from, to, start, end
        case durationMinutes = "duration_minutes"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard let s = try c.decodeIfPresent(Date.self, forKey: .from)
                ?? c.decodeIfPresent(Date.self, forKey: .start) else {
            throw DecodingError.keyNotFound(CodingKeys.from, .init(
                codingPath: c.codingPath,
                debugDescription: "wake-up window has neither `from` nor `start`"))
        }
        start = s
        end = try c.decodeIfPresent(Date.self, forKey: .to)
            ?? c.decodeIfPresent(Date.self, forKey: .end)
        durationMinutes = try c.decodeIfPresent(Int.self, forKey: .durationMinutes)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(start, forKey: .from)
        try c.encodeIfPresent(end, forKey: .to)
        try c.encodeIfPresent(durationMinutes, forKey: .durationMinutes)
    }
}
