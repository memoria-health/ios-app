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
      "battery_percent": 78,
      "cameras_paused": false,
      "photo_storage_key": "5b1c0312-44a0-4f9d-9a3a-2d4f44a1f0bb.jpg",
      "created_at": "2026-04-01T10:00:00+00:00",
      "updated_at": "2026-05-21T22:18:00+00:00"
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
      "battery_percent": null,
      "cameras_paused": false,
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
      "livekit_identity": "cam_ce110001",
      "last_seen_at": "2026-05-21T22:20:00+00:00",
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
      "livekit_identity": null,
      "last_seen_at": null,
      "created_at": "2026-04-01T10:05:00+00:00"
    }
    """

    static let detectorPreset = """
    {
      "id": "de110001-0000-4000-8000-000000000001",
      "patient_id": "5b1c0312-44a0-4f9d-9a3a-2d4f44a1f0bb",
      "name": "Falls",
      "icon_name": "figure.fall",
      "description": "Detects falls in any room.",
      "category": "safety",
      "source": "preset",
      "shape": "point_in_time",
      "where_scope": "ALL ROOMS",
      "when_scope": "ALWAYS",
      "sensitivity": "high",
      "is_on": true,
      "custom_prompt": null,
      "created_at": "2026-04-01T10:00:00+00:00",
      "updated_at": "2026-04-01T10:00:00+00:00"
    }
    """

    static let detectorCustom = """
    {
      "id": "de110002-0000-4000-8000-000000000002",
      "patient_id": "5b1c0312-44a0-4f9d-9a3a-2d4f44a1f0bb",
      "name": "Took meds",
      "icon_name": "pills",
      "description": "Patient took morning + evening medication.",
      "category": "routine",
      "source": "custom",
      "shape": "state",
      "where_scope": "KITCHEN",
      "when_scope": "8 AM, 8 PM ±1H",
      "sensitivity": "standard",
      "is_on": true,
      "custom_prompt": "Confirm patient swallowed pills next to the dispenser.",
      "created_at": "2026-04-02T15:30:00+00:00",
      "updated_at": "2026-04-02T15:30:00+00:00"
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
