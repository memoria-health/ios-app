import Foundation

/// One face embedding row in the patient's Re-ID gallery. Mirrors
/// `nemara-backend/src/schemas/face_embedding.py:FaceEmbeddingResponse`.
///
/// Two row kinds:
///   - `.selfie`: caregiver-uploaded during onboarding (10-15 captures)
///   - `.harvested`: backend auto-added a wall-cam face crop after a
///     high-confidence Re-ID lock. Closes the selfie-to-wall-cam
///     domain gap over time
///
/// The raw 512-dim embedding bytes are NEVER returned over the wire
/// (privacy + uselessness to a client). This struct carries only the
/// metadata the dashboard renders.
struct FaceEmbedding: Identifiable, Hashable, Sendable, Codable {
    enum Source: String, Sendable, Codable {
        case selfie
        case harvested
    }

    enum Status: String, Sendable, Codable {
        case processing
        case ready
        case failed
    }

    let id: UUID
    let patientId: UUID
    let source: Source
    let status: Status
    let detScore: Float
    let failureReason: String?
    let createdAt: Date
}


/// Summary numbers driving the iOS PatientSettings card AND the web
/// dashboard status card. Mirrors
/// `nemara-backend/src/schemas/face_embedding.py:FaceEnrollmentSummary`.
///
/// The status copy rendered from this struct is BYTE-IDENTICAL across
/// iOS and web — caregivers see the same numbers regardless of device.
struct FaceEnrollmentSummary: Sendable, Codable {
    let selfieCount: Int
    let harvestedCount: Int
    let processingCount: Int
    let failedCount: Int
    let lastUpdate: Date?

    /// True when the patient has at least one ready selfie embedding.
    /// Drives the "Enrolled" vs "Not enrolled" branch in the status
    /// card.
    var isEnrolled: Bool { selfieCount > 0 }

    /// True when an enrollment batch is mid-processing — caregiver
    /// sees "Processing N photos..." instead of the steady-state copy.
    var isProcessing: Bool { processingCount > 0 }
}
