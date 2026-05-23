import Foundation

/// Errors surfaced from `NemaraAPIClient`. Maps to nemara-backend's error
/// envelope (FastAPI's `{"detail": ...}` shape).
enum APIError: Error, Equatable, Sendable {
    /// Bad request shape — likely a client-side bug.
    case badRequest(message: String)
    /// 401 — token missing/expired. Caller should sign out.
    case unauthorized
    /// 403 — authenticated but forbidden.
    case forbidden
    /// 404 — entity does not exist.
    case notFound
    /// 409 — request conflicts with the current resource state. The
    /// reason string is the backend's `{"detail": "code"}` value
    /// (e.g. "clip_not_ready"); callers compare against it to decide
    /// whether to surface a user-facing message or retry later.
    case conflict(reason: String)
    /// 5xx — backend is unhealthy.
    case serverError(code: String?, message: String?)
    /// Network reachability — no response received.
    case offline
    /// Decoding failure — response shape didn't match the contract.
    /// Usually means the backend's pydantic schema drifted from
    /// the Swift `Codable` model. The Codable round-trip tests under
    /// `NemaraCaregiverTests/Models/` exist to catch this earlier.
    case decoding(underlying: String)
    /// Catch-all for unexpected paths.
    case other(message: String)
}

extension APIError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .badRequest(let m):       return "Bad request: \(m)"
        case .unauthorized:            return "You've been signed out. Please log in again."
        case .forbidden:               return "You don't have access to this."
        case .notFound:                return "That isn't here anymore."
        case .conflict(let r):         return "The server isn't ready yet (\(r))."
        case .serverError(_, let m):   return m ?? "The server is having a moment. Try again."
        case .offline:                 return "You're offline."
        case .decoding(let u):         return "Couldn't read the response (\(u))."
        case .other(let m):            return m
        }
    }
}
