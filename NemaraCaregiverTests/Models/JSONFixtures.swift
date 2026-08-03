import Foundation

/// JSON fixtures lifted from real nemara-backend responses. These are
/// the canonical wire shape the iOS Codable models must decode without
/// loss. When a backend response changes, refresh the fixture and the
/// matching round-trip test will catch the drift before users do.
enum JSONFixtures {

    static let caregiver = """
    {
      "id": "a4f1c2d8-5c7e-4dab-9c2f-72e1f3b0aa01",
      "display_name": "Jane Patel",
      "email": "jane@patel.co",
      "phone": "+14155550123",
      "created_at": "2026-05-01T14:23:11.182734+00:00",
      "updated_at": "2026-05-12T18:01:02.000000+00:00"
    }
    """

    static let caregiverNoPhone = """
    {
      "id": "b1e2c3d4-5678-49ab-9cde-0123456789ab",
      "display_name": "Aaron Lee",
      "email": "aaron@example.com",
      "phone": null,
      "created_at": "2026-04-30T00:00:00+00:00",
      "updated_at": "2026-04-30T00:00:00+00:00"
    }
    """

    static let patient = """
    {
      "id": "5b1c0312-44a0-4f9d-9a3a-2d4f44a1f0bb",
      "caregiver_id": "a4f1c2d8-5c7e-4dab-9c2f-72e1f3b0aa01",
      "full_name": "Margaret O'Brien",
      "preferred_name": "Maggie",
      "date_of_birth": "1944-05-12",
      "gender": "Female",
      "relation": "parent",
      "home_address": "12 Cedar Ln, Berkeley CA",
      "state": "critical",
      "status_line": "Possible fall, living room",
      "last_event_at": "2026-05-21T22:18:00+00:00",
      "cameras_paused": false,
      "email_alerts_enabled": true,
      "email_alert_recipients": ["kate@example.com"],
      "data_collection_enabled": false,
      "photo_storage_key": "5b1c0312-44a0-4f9d-9a3a-2d4f44a1f0bb.jpg",
      "created_at": "2026-04-01T10:00:00+00:00",
      "updated_at": "2026-05-21T22:18:00+00:00"
    }
    """

    /// An OLDER backend's patient row: only the launch columns. Every
    /// field added since (email alerts, data collection, residency,
    /// audio kill, cameras_paused) is absent. Sign-in loads patients
    /// first, so a hard decode of any of these takes login down.
    static let patientLegacyBackend = """
    {
      "id": "22222222-3333-4444-5555-666666666666",
      "caregiver_id": "a4f1c2d8-5c7e-4dab-9c2f-72e1f3b0aa01",
      "full_name": "Arthur Reed",
      "preferred_name": "Art",
      "relation": "parent",
      "state": "calm",
      "status_line": "All quiet",
      "created_at": "2026-05-22T09:00:00+00:00",
      "updated_at": "2026-05-22T09:00:00+00:00"
    }
    """

    static let patientMinimal = """
    {
      "id": "11111111-2222-3333-4444-555555555555",
      "caregiver_id": "a4f1c2d8-5c7e-4dab-9c2f-72e1f3b0aa01",
      "full_name": "Henry Gold",
      "preferred_name": "Henry",
      "date_of_birth": null,
      "gender": null,
      "relation": "other",
      "home_address": null,
      "state": "calm",
      "status_line": "All quiet",
      "last_event_at": null,
      "cameras_paused": false,
      "email_alerts_enabled": false,
      "email_alert_recipients": [],
      "data_collection_enabled": false,
      "photo_storage_key": null,
      "created_at": "2026-05-22T09:00:00+00:00",
      "updated_at": "2026-05-22T09:00:00+00:00"
    }
    """

    static let camera = """
    {
      "id": "ce110001-0000-4000-8000-000000000001",
      "patient_id": "5b1c0312-44a0-4f9d-9a3a-2d4f44a1f0bb",
      "display_id": 1,
      "room": "Living room",
      "icon_name": "tv",
      "online": true,
      "disabled": false,
      "ai_paused": false,
      "desired_state": "connected",
      "paired": true,
      "app_present": true,
      "livekit_identity": "cam_ce110001",
      "created_at": "2026-04-01T10:05:00+00:00"
    }
    """

    static let cameraOffline = """
    {
      "id": "ce110002-0000-4000-8000-000000000002",
      "patient_id": "5b1c0312-44a0-4f9d-9a3a-2d4f44a1f0bb",
      "display_id": 2,
      "room": "Kitchen",
      "icon_name": "fork.knife",
      "online": false,
      "disabled": false,
      "ai_paused": false,
      "desired_state": "disconnected",
      "paired": false,
      "livekit_identity": null,
      "created_at": "2026-04-01T10:05:00+00:00"
    }
    """

    /// Preset detector as the current backend sends it: `alert_trigger` +
    /// `is_sustained` present, room scope carried by `where_rooms`, and no
    /// `where_scope` key at all (dropped from the API 2026-07-28).
    static let detectorPreset = """
    {
      "id": "de110001-0000-4000-8000-000000000001",
      "patient_id": "5b1c0312-44a0-4f9d-9a3a-2d4f44a1f0bb",
      "name": "Falls",
      "icon_name": "figure.fall",
      "description": "Detects falls in any room.",
      "category": "safety",
      "source": "preset",
      "alert_trigger": "leading",
      "is_sustained": false,
      "duration_seconds": null,
      "where_rooms": null,
      "when_scope": "ALWAYS",
      "sensitivity": "high",
      "is_on": true,
      "custom_prompt": null,
      "identifier": "fall",
      "accuracy_caveat": false,
      "created_at": "2026-04-01T10:00:00+00:00",
      "updated_at": "2026-04-01T10:00:00+00:00"
    }
    """

    /// Custom detector exercising the sustained shape: `duration` trigger
    /// with a threshold, an episode gap, and a multi-room scope.
    static let detectorCustom = """
    {
      "id": "de110002-0000-4000-8000-000000000002",
      "patient_id": "5b1c0312-44a0-4f9d-9a3a-2d4f44a1f0bb",
      "name": "Took meds",
      "icon_name": "pills",
      "description": "Patient took morning + evening medication.",
      "category": "routine",
      "source": "custom",
      "alert_trigger": "duration",
      "is_sustained": true,
      "duration_seconds": 900,
      "where_rooms": ["KITCHEN", "DINING ROOM"],
      "when_scope": "8 AM, 8 PM ±1H",
      "episode_gap_seconds": 300,
      "sensitivity": "standard",
      "is_on": true,
      "custom_prompt": "Confirm patient swallowed pills next to the dispenser.",
      "identifier": "custom_a1b2c3d4",
      "accuracy_caveat": true,
      "created_at": "2026-04-02T15:30:00+00:00",
      "updated_at": "2026-04-02T15:30:00+00:00"
    }
    """

    /// An OLDER backend's response: carries only the columns that predate
    /// the alert-trigger migration. Everything the app added since is
    /// absent. This is what the tolerant decoder in `Detector` exists for —
    /// a hard `decode` of any missing key here throws `keyNotFound` and
    /// takes sign-in down with it.
    static let detectorLegacyBackend = """
    {
      "id": "de110003-0000-4000-8000-000000000003",
      "patient_id": "5b1c0312-44a0-4f9d-9a3a-2d4f44a1f0bb",
      "name": "Wandering",
      "icon_name": "figure.walk",
      "description": "Patient left through an exit door.",
      "category": "safety",
      "source": "preset",
      "when_scope": "10 PM - 6 AM",
      "sensitivity": "high",
      "is_on": true,
      "created_at": "2026-04-03T08:00:00+00:00",
      "updated_at": "2026-04-03T08:00:00+00:00"
    }
    """

    static let event = """
    {
      "id": "ee110001-0000-4000-8000-000000000001",
      "patient_id": "5b1c0312-44a0-4f9d-9a3a-2d4f44a1f0bb",
      "detector_id": "de110001-0000-4000-8000-000000000001",
      "camera_id": "ce110001-0000-4000-8000-000000000001",
      "category": "safety",
      "source": "preset",
      "icon_name": "figure.fall",
      "title": "Possible fall",
      "location": "Living room",
      "occurred_at": "2026-05-21T22:18:00+00:00",
      "has_clip": true,
      "narrative": "Patient appears to have lost balance near the couch.",
      "opened": true,
      "reviewed": false,
      "review_choice": null,
      "review_notes": null,
      "reviewed_at": null,
      "clip_storage_key": "events/ee110001-0000-4000-8000-000000000001.mp4",
      "created_at": "2026-05-21T22:18:01+00:00"
    }
    """

    static let eventReviewed = """
    {
      "id": "ee110002-0000-4000-8000-000000000002",
      "patient_id": "5b1c0312-44a0-4f9d-9a3a-2d4f44a1f0bb",
      "detector_id": null,
      "camera_id": null,
      "category": "routine",
      "source": "custom",
      "icon_name": "pills",
      "title": "Took meds",
      "location": "Kitchen",
      "occurred_at": "2026-05-21T08:05:00+00:00",
      "has_clip": false,
      "narrative": "Patient retrieved morning pill dispenser.",
      "opened": true,
      "reviewed": true,
      "review_choice": "correct",
      "review_notes": "Confirmed, watched the clip.",
      "reviewed_at": "2026-05-21T09:00:00+00:00",
      "clip_storage_key": null,
      "created_at": "2026-05-21T08:05:01+00:00"
    }
    """

    static let eventList = """
    {
      "items": [\(event), \(eventReviewed)],
      "next_cursor": "eyJvY2N1cnJlZF9hdCI6Mn0="
    }
    """

    static let eventListLastPage = """
    {
      "items": [\(eventReviewed)],
      "next_cursor": null
    }
    """
}
