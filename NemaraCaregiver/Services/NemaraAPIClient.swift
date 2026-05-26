import Foundation
import Observation
import Realtime
import Supabase

/// `NemaraAPIClient` — single source of truth for caregiver-facing
/// nemara-backend state and the only HTTP client in the app.
///
/// Holds observable collections (`patients`, `camerasByPatient`, etc.)
/// that views read directly. Mutating endpoints update the local state
/// with the row returned from the server (eager write-through). A
/// later step layers Supabase Realtime on top so updates originating
/// from other clients land here too.
///
/// **Why state + HTTP live on the same object.** Range used the
/// store-vs-service split because it had mock + live wolf clients +
/// LiveKit + a transcript WS — multiple data sources with different
/// lifecycles. Nemara only has one data source. Folding state into
/// the API client keeps the seam count at one and avoids a redundant
/// shim layer that would just forward calls.
@Observable
@MainActor
final class NemaraAPIClient {

    // MARK: - Observable state

    var patients: [Patient] = []
    var camerasByPatient: [UUID: [Camera]] = [:]
    var detectorsByPatient: [UUID: [Detector]] = [:]
    var eventsByPatient: [UUID: [DetectionEvent]] = [:]

    /// `true` while `bootstrap()` is in flight. Roster + tabs use this
    /// to show a single loading affordance instead of three per-screen
    /// spinners.
    var isLoading: Bool = false

    // MARK: - Dependencies

    private let baseURL: URL
    private let session: URLSession
    private let tokenProvider: () async -> String?
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder

    /// Shared Supabase client (used for the Realtime channels opened
    /// from `bootstrap()`).
    let supabase: SupabaseClient

    /// One channel per replicated table. Held so `teardown()` can
    /// `unsubscribe()` cleanly on sign-out.
    private var channels: [RealtimeChannelV2] = []

    /// Long-running tasks that consume each channel's `AsyncStream`.
    /// Cancelled in `teardown()`.
    private var streamTasks: [Task<Void, Never>] = []

    init(
        baseURL: URL = AppConfig.backendURL,
        supabaseClient: SupabaseClient,
        tokenProvider: @escaping () async -> String?,
        session: URLSession = .shared,
    ) {
        self.baseURL = baseURL
        self.supabase = supabaseClient
        self.tokenProvider = tokenProvider
        self.session = session
        self.decoder = NemaraJSON.decoder()
        self.encoder = NemaraJSON.encoder()
    }

    // MARK: - Lifecycle

    /// Load the caregiver's roster + every per-patient sub-collection in
    /// parallel, then open Supabase Realtime channels so changes that
    /// originate from other clients (or scenario-CLI fires) land here
    /// without polling.
    func bootstrap() async throws {
        isLoading = true
        defer { isLoading = false }

        try await loadPatients()

        try await withThrowingTaskGroup(of: Void.self) { group in
            for p in patients {
                group.addTask { try await self.loadCameras(forPatient: p.id) }
                group.addTask { try await self.loadDetectors(forPatient: p.id) }
                group.addTask { try await self.loadEventsFirstPage(forPatient: p.id) }
            }
            try await group.waitForAll()
        }

        await openRealtimeChannels()
    }

    /// Refetch the full roster + every per-patient sub-collection.
    /// Same data path as `bootstrap()` but does NOT re-open Realtime
    /// channels (those stay attached from the original bootstrap).
    /// Bound to pull-to-refresh on the roster — the escape hatch when
    /// Realtime drops a row change (e.g. a delete via Supabase Studio).
    func refresh() async throws {
        isLoading = true
        defer { isLoading = false }

        try await loadPatients()
        // Drop sub-collections for patients that no longer exist —
        // loadPatients() refreshed `patients` to the server's view,
        // so any entry in the by-patient dicts whose patient is gone
        // is stale and would otherwise leak.
        let liveIds = Set(patients.map(\.id))
        camerasByPatient = camerasByPatient.filter { liveIds.contains($0.key) }
        detectorsByPatient = detectorsByPatient.filter { liveIds.contains($0.key) }
        eventsByPatient = eventsByPatient.filter { liveIds.contains($0.key) }

        try await withThrowingTaskGroup(of: Void.self) { group in
            for p in patients {
                group.addTask { try await self.loadCameras(forPatient: p.id) }
                group.addTask { try await self.loadDetectors(forPatient: p.id) }
                group.addTask { try await self.loadEventsFirstPage(forPatient: p.id) }
            }
            try await group.waitForAll()
        }
    }

    /// Clear all state and disconnect from Realtime. Called on sign-out.
    func teardown() async {
        for t in streamTasks { t.cancel() }
        streamTasks.removeAll()
        for ch in channels { await ch.unsubscribe() }
        channels.removeAll()
        patients = []
        camerasByPatient = [:]
        detectorsByPatient = [:]
        eventsByPatient = [:]
    }

    // MARK: - Identity (POST/GET/PATCH /v1/me)

    func provisionMe(displayName: String, phone: String? = nil) async throws -> Caregiver {
        try await sendJSON(
            method: "POST", path: "/v1/me",
            body: CreateCaregiverRequest(displayName: displayName, phone: phone),
        )
    }

    func me() async throws -> Caregiver {
        try await sendNoBody(method: "GET", path: "/v1/me")
    }

    func updateMe(displayName: String? = nil, phone: String? = nil) async throws -> Caregiver {
        try await sendJSON(
            method: "PATCH", path: "/v1/me",
            body: UpdateCaregiverRequest(displayName: displayName, phone: phone),
        )
    }

    // MARK: - Device tokens (POST /v1/me/devices)

    /// Register or refresh an APNs device token for the caller.
    /// Idempotent on `apnsToken` — the backend updates the existing
    /// row rather than inserting a duplicate, so calling this on every
    /// launch is the intended pattern.
    @discardableResult
    func registerDeviceToken(
        apnsToken: String,
        bundleId: String = "co.sunny.nemara",
        environment: APNsEnvironment,
    ) async throws -> DeviceResponse {
        try await sendJSON(
            method: "POST", path: "/v1/me/devices",
            body: RegisterDeviceRequest(
                apnsToken: apnsToken,
                bundleId: bundleId,
                environment: environment,
            ),
        )
    }

    // MARK: - Patients (GET/POST/GET/PATCH/DELETE /v1/patients...)

    func loadPatients() async throws {
        let list: [Patient] = try await sendNoBody(method: "GET", path: "/v1/patients")
        patients = list
    }

    func createPatient(_ body: CreatePatientRequest) async throws -> Patient {
        let created: Patient = try await sendJSON(method: "POST", path: "/v1/patients", body: body)
        patients.append(created)
        return created
    }

    func updatePatient(_ id: UUID, _ body: UpdatePatientRequest) async throws -> Patient {
        let updated: Patient = try await sendJSON(
            method: "PATCH", path: "/v1/patients/\(id.uuidString.lowercased())", body: body,
        )
        if let idx = patients.firstIndex(where: { $0.id == updated.id }) {
            patients[idx] = updated
        }
        return updated
    }

    /// Upload (or replace) a patient's avatar. Multipart with one part
    /// — `photo` — pre-encoded as JPEG by the caller. Returns the
    /// canonical patient row with `photoStorageKey` populated; we
    /// also update the local `patients` array in place so the roster
    /// re-renders without a refetch.
    @discardableResult
    func uploadPatientPhoto(
        _ patientId: UUID,
        imageData: Data,
        contentType: String,
    ) async throws -> Patient {
        let boundary = "nemara-\(UUID().uuidString)"
        let body = _multipartBody(
            boundary: boundary,
            partName: "photo",
            filename: contentType == "image/png" ? "avatar.png" : "avatar.jpg",
            contentType: contentType,
            data: imageData,
        )
        var request = try await makeRequest(
            method: "POST",
            path: "/v1/patients/\(patientId.uuidString.lowercased())/photo",
        )
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type",
        )
        request.httpBody = body
        let updated: Patient = try await sendRequest(request)
        if let idx = patients.firstIndex(where: { $0.id == patientId }) {
            patients[idx] = updated
        }
        return updated
    }

    /// Mint a short-lived signed URL for a patient's avatar. Returns
    /// `nil` when no photo is uploaded (backend returns 404). Throws
    /// on any other error.
    func patientPhotoURL(_ patientId: UUID) async throws -> URL? {
        do {
            let response: PhotoURLResponse = try await sendNoBody(
                method: "GET",
                path: "/v1/patients/\(patientId.uuidString.lowercased())/photo-url",
            )
            return response.url
        } catch APIError.notFound {
            return nil
        }
    }

    /// Remove the patient's avatar. Server is idempotent — 204 even
    /// if there was no prior photo. Local state mutates immediately
    /// so the UI updates without a roundtrip refetch.
    func deletePatientPhoto(_ patientId: UUID) async throws {
        try await sendNoBodyVoid(
            method: "DELETE",
            path: "/v1/patients/\(patientId.uuidString.lowercased())/photo",
        )
        if let idx = patients.firstIndex(where: { $0.id == patientId }) {
            var p = patients[idx]
            p.photoStorageKey = nil
            patients[idx] = p
        }
    }

    // MARK: - Face enrollment (Re-ID)

    /// Upload N selfies for the patient's Re-ID gallery. Multipart
    /// with one `photos` part per image. Server returns the
    /// placeholder rows (status=processing); the caller polls
    /// `faceEnrollmentSummary` for completion.
    @discardableResult
    func submitFaceEmbeddings(
        _ patientId: UUID,
        photos: [Data],
    ) async throws -> [FaceEmbedding] {
        precondition(!photos.isEmpty, "submitFaceEmbeddings requires at least one photo")
        let boundary = "nemara-\(UUID().uuidString)"
        let body = _multipartManyParts(
            boundary: boundary,
            partName: "photos",
            contentType: "image/jpeg",
            datas: photos,
        )
        var request = try await makeRequest(
            method: "POST",
            path: "/v1/patients/\(patientId.uuidString.lowercased())/face-embeddings",
        )
        request.setValue(
            "multipart/form-data; boundary=\(boundary)",
            forHTTPHeaderField: "Content-Type",
        )
        request.httpBody = body
        return try await sendRequest(request)
    }

    /// Pull the status-card summary for a patient. Renders the same
    /// numbers the web dashboard shows.
    func faceEnrollmentSummary(_ patientId: UUID) async throws -> FaceEnrollmentSummary {
        try await sendNoBody(
            method: "GET",
            path: "/v1/patients/\(patientId.uuidString.lowercased())/face-embeddings/summary",
        )
    }

    /// List all face embeddings for the patient. The dashboard uses
    /// this when the user wants a full breakdown; the status card
    /// uses the summary endpoint above instead.
    func listFaceEmbeddings(_ patientId: UUID) async throws -> [FaceEmbedding] {
        try await sendNoBody(
            method: "GET",
            path: "/v1/patients/\(patientId.uuidString.lowercased())/face-embeddings",
        )
    }

    /// Delete one face embedding. The backend cascades to delete the
    /// Storage object too. Used by future audit UI (v0.1).
    func deleteFaceEmbedding(_ embeddingId: UUID) async throws {
        try await sendNoBodyVoid(
            method: "DELETE",
            path: "/v1/face-embeddings/\(embeddingId.uuidString.lowercased())",
        )
    }

    /// Compose a multipart/form-data body with N parts that all share
    /// the same field name (the `photos` field is repeated per the
    /// FastAPI convention for `list[UploadFile]`).
    private func _multipartManyParts(
        boundary: String,
        partName: String,
        contentType: String,
        datas: [Data],
    ) -> Data {
        var body = Data()
        for (idx, data) in datas.enumerated() {
            body.append("--\(boundary)\r\n".data(using: .utf8)!)
            body.append(
                "Content-Disposition: form-data; name=\"\(partName)\"; filename=\"photo_\(idx).jpg\"\r\n"
                    .data(using: .utf8)!,
            )
            body.append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
            body.append(data)
            body.append("\r\n".data(using: .utf8)!)
        }
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }

    /// Compose a multipart/form-data body for a single binary part.
    /// We hand-roll this instead of pulling in a multipart library —
    /// it's one part, the boundary is fresh per call, and avoiding
    /// the dep is preferable to importing one for a single use case.
    private func _multipartBody(
        boundary: String,
        partName: String,
        filename: String,
        contentType: String,
        data: Data,
    ) -> Data {
        var body = Data()
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append(
            "Content-Disposition: form-data; name=\"\(partName)\"; filename=\"\(filename)\"\r\n"
                .data(using: .utf8)!,
        )
        body.append("Content-Type: \(contentType)\r\n\r\n".data(using: .utf8)!)
        body.append(data)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)
        return body
    }

    func deletePatient(_ id: UUID) async throws {
        // 404 here means the row is already gone server-side (e.g.
        // a prior delete via Supabase Studio, or a Realtime DELETE
        // we missed). Caller's intent — "this patient should not
        // exist" — is satisfied either way, so treat it as success
        // and proceed to clean up local state.
        do {
            try await sendNoBodyVoid(
                method: "DELETE",
                path: "/v1/patients/\(id.uuidString.lowercased())",
            )
        } catch APIError.notFound {
            // fall through to local cleanup
        }
        patients.removeAll { $0.id == id }
        camerasByPatient.removeValue(forKey: id)
        detectorsByPatient.removeValue(forKey: id)
        eventsByPatient.removeValue(forKey: id)
    }

    // MARK: - Cameras (GET / DELETE / POST pairing-code)

    func loadCameras(forPatient pid: UUID) async throws {
        let cams: [Camera] = try await sendNoBody(
            method: "GET", path: "/v1/patients/\(pid.uuidString.lowercased())/cameras",
        )
        camerasByPatient[pid] = cams
    }

    /// Mint a 6-digit pairing code for a new wall phone on this
    /// patient. Server inserts a placeholder `cameras` row with
    /// `online=false` + the code valid for ~10min; the wall phone
    /// completes the exchange via `POST /v1/cameras/pair`. We
    /// optimistically refresh the patient's camera list so the
    /// placeholder row appears (it'll flip to `online=true` once the
    /// phone connects, via Realtime).
    func createPairingCode(
        forPatient pid: UUID,
        room: String,
        iconName: String = "tv",
    ) async throws -> CreatePairingCodeResponse {
        let response: CreatePairingCodeResponse = try await sendJSON(
            method: "POST",
            path: "/v1/patients/\(pid.uuidString.lowercased())/cameras/pairing-code",
            body: CreatePairingCodeRequest(room: room, iconName: iconName),
        )
        try await loadCameras(forPatient: pid)
        return response
    }

    func deleteCamera(_ id: UUID) async throws {
        try await sendNoBodyVoid(method: "DELETE", path: "/v1/cameras/\(id.uuidString.lowercased())")
        for (pid, cams) in camerasByPatient {
            if let idx = cams.firstIndex(where: { $0.id == id }) {
                camerasByPatient[pid]?.remove(at: idx)
                break
            }
        }
    }

    /// Flip the user-facing toggle fields on a camera: `disabled`
    /// (pause AI calls; LiveKit stays connected) and `desiredState`
    /// (hard disconnect from LiveKit — phone polls
    /// `/v1/cameras/me/desired-state` every 1s and reconciles).
    ///
    /// Locally we update the cached row optimistically with the
    /// response; the Realtime sub on `cameras` would also pick this
    /// up but doing it now keeps the UI snappy.
    func updateCamera(_ id: UUID, _ body: UpdateCameraRequest) async throws -> Camera {
        let updated: Camera = try await sendJSON(
            method: "PATCH",
            path: "/v1/cameras/\(id.uuidString.lowercased())",
            body: body,
        )
        if var arr = camerasByPatient[updated.patientId],
           let idx = arr.firstIndex(where: { $0.id == updated.id }) {
            arr[idx] = updated
            camerasByPatient[updated.patientId] = arr
        }
        return updated
    }

    /// Fetch the set of detector IDs currently assigned to a camera.
    /// The per-camera detail view cross-references this against the
    /// patient's full detector list to render assignment toggles.
    func getCameraDetectors(_ id: UUID) async throws -> [UUID] {
        let resp: CameraDetectorsResponse = try await sendNoBody(
            method: "GET",
            path: "/v1/cameras/\(id.uuidString.lowercased())/detectors",
        )
        return resp.detectorIds
    }

    /// Replace a camera's detector assignment set with exactly the
    /// given IDs. Backend rejects (422) if any ID belongs to a
    /// different patient. Takes effect on the next detector tick —
    /// `services/detection/registry.py` reads the join table per
    /// call, no in-process cache to invalidate.
    func setCameraDetectors(_ id: UUID, detectorIds: [UUID]) async throws -> [UUID] {
        let resp: CameraDetectorsResponse = try await sendJSON(
            method: "PUT",
            path: "/v1/cameras/\(id.uuidString.lowercased())/detectors",
            body: SetCameraDetectorsRequest(detectorIds: detectorIds),
        )
        return resp.detectorIds
    }

    // MARK: - Detectors

    func loadDetectors(forPatient pid: UUID) async throws {
        let list: [Detector] = try await sendNoBody(
            method: "GET", path: "/v1/patients/\(pid.uuidString.lowercased())/detectors",
        )
        detectorsByPatient[pid] = list
    }

    func createCustomDetector(forPatient pid: UUID, _ body: CreateDetectorRequest) async throws -> Detector {
        let created: Detector = try await sendJSON(
            method: "POST", path: "/v1/patients/\(pid.uuidString.lowercased())/detectors", body: body,
        )
        detectorsByPatient[pid, default: []].append(created)
        return created
    }

    func updateDetector(_ id: UUID, _ body: UpdateDetectorRequest) async throws -> Detector {
        let updated: Detector = try await sendJSON(
            method: "PATCH", path: "/v1/detectors/\(id.uuidString.lowercased())", body: body,
        )
        if var arr = detectorsByPatient[updated.patientId],
           let idx = arr.firstIndex(where: { $0.id == updated.id }) {
            arr[idx] = updated
            detectorsByPatient[updated.patientId] = arr
        }
        return updated
    }

    func deleteDetector(_ id: UUID) async throws {
        try await sendNoBodyVoid(method: "DELETE", path: "/v1/detectors/\(id.uuidString.lowercased())")
        for (pid, arr) in detectorsByPatient {
            if let idx = arr.firstIndex(where: { $0.id == id }) {
                detectorsByPatient[pid]?.remove(at: idx)
                break
            }
        }
    }

    // MARK: - Events

    /// Load the first page of events (default 30, server-sorted newest
    /// first) and replace the local cache for that patient.
    func loadEventsFirstPage(
        forPatient pid: UUID,
        filter: EventFilter = .all,
    ) async throws {
        let page = try await loadEventsPage(forPatient: pid, filter: filter, cursor: nil)
        eventsByPatient[pid] = page.items
    }

    /// Cursor-paginated fetch. Returns the page + next cursor; the
    /// caller decides whether to append into local state.
    func loadEventsPage(
        forPatient pid: UUID,
        filter: EventFilter,
        cursor: String?,
    ) async throws -> EventListResponse {
        var query: [URLQueryItem] = [.init(name: "filter", value: filter.rawValue)]
        if let cursor { query.append(.init(name: "cursor", value: cursor)) }
        return try await sendNoBody(
            method: "GET",
            path: "/v1/patients/\(pid.uuidString.lowercased())/events",
            query: query,
        )
    }

    /// Fetch a short-lived signed URL for the event's archived clip.
    /// Returns `nil` when the clip isn't ready yet (backend responds
    /// with 409 `clip_not_ready` — caregiver app shows the
    /// "processing…" placeholder until Realtime flips `has_clip=true`).
    /// Throws on any other error.
    func clipURL(forEvent eventId: UUID) async throws -> URL? {
        do {
            let response: ClipURLResponse = try await sendNoBody(
                method: "GET",
                path: "/v1/events/\(eventId.uuidString.lowercased())/clip-url",
            )
            return response.url
        } catch APIError.conflict {
            return nil
        }
    }

    func updateEvent(_ id: UUID, _ body: UpdateEventRequest) async throws -> DetectionEvent {
        let updated: DetectionEvent = try await sendJSON(
            method: "PATCH", path: "/v1/events/\(id.uuidString.lowercased())", body: body,
        )
        if var arr = eventsByPatient[updated.patientId],
           let idx = arr.firstIndex(where: { $0.id == updated.id }) {
            arr[idx] = updated
            eventsByPatient[updated.patientId] = arr
        }
        return updated
    }

    // MARK: - LiveKit (POST /v1/livekit/token) + Talk

    /// Mint a viewer JWT for the patient's `patient_<id>` room. Used by
    /// the Live tab to subscribe to wall-phone publishers.
    func mintViewerToken(forPatient pid: UUID) async throws -> MintTokenResponse {
        try await mintToken(forPatient: pid, role: "viewer")
    }

    /// Mint a broadcaster JWT — same room, plus `canPublish=true` so
    /// the caregiver can stream their mic during Talk mode.
    func mintBroadcasterToken(forPatient pid: UUID) async throws -> MintTokenResponse {
        try await mintToken(forPatient: pid, role: "broadcaster")
    }

    private func mintToken(forPatient pid: UUID, role: String) async throws -> MintTokenResponse {
        // Identity is informational — server validates the prefix and
        // re-mints with whatever we send. `caregiver_<id>` makes audit
        // logs on the LiveKit side legible.
        guard let caregiverID = await tokenProviderCaregiverId() else {
            throw APIError.unauthorized
        }
        let body = MintTokenRequest(
            room: "patient_\(pid.uuidString.lowercased())",
            // LiveKit treats `identity` as a unique participant key per
            // room. The web dashboard uses `caregiver_<uuid>_web`; this
            // app uses `caregiver_<uuid>_ios` — keeping them distinct
            // lets the SAME caregiver subscribe to a patient's cameras
            // from BOTH devices simultaneously. Without the `_ios`
            // suffix, LiveKit kicks the older session whenever the
            // other client (web) connects with the same identity.
            identity: "caregiver_\(caregiverID.uuidString.lowercased())_ios",
            role: role,
        )
        return try await sendJSON(method: "POST", path: "/v1/livekit/token", body: body)
    }

    /// Per-caregiver identity helper. Reaches into the auth service via
    /// the same token-provider closure so we don't widen the constructor.
    /// Returns nil if there's no signed-in caregiver — the caller maps
    /// that to `APIError.unauthenticated`.
    private func tokenProviderCaregiverId() async -> UUID? {
        // The token-provider closure can't return a UUID, so we peek at
        // the Supabase client we already hold. `auth.session.user.id` is
        // the canonical caregiver UUID for the current JWT.
        let user = try? await supabase.auth.session.user
        return user?.id
    }

    /// Suggestion endpoint — the Live tab uses this to default the
    /// carousel to whichever camera the patient is most likely in
    /// front of. Nil cameraId means "no qualifying analyses row in the
    /// last 30s"; fall back to the first online camera client-side.
    func getActiveCamera(forPatient pid: UUID) async throws -> UUID? {
        let response: ActiveCameraResponse = try await sendNoBody(
            method: "GET",
            path: "/v1/patients/\(pid.uuidString.lowercased())/active-camera",
        )
        return response.cameraId
    }

    /// Open (or transfer) a call to one specific camera. Backend
    /// sends `is_active=true` to that camera and `is_active=false` to
    /// every sibling — re-POSTing with a different `cameraId`
    /// transfers an active call atomically.
    func startTalk(forPatient pid: UUID, cameraId: UUID) async throws {
        try await sendJSONVoid(
            method: "POST",
            path: "/v1/patients/\(pid.uuidString.lowercased())/talk/start",
            body: TalkStartRequest(cameraId: cameraId),
        )
    }

    /// Close any open call. Sends `is_active=false` to every camera in
    /// the patient's room. Idempotent.
    func endTalk(forPatient pid: UUID) async throws {
        try await sendNoBodyVoid(
            method: "POST",
            path: "/v1/patients/\(pid.uuidString.lowercased())/talk/end",
        )
    }

    // MARK: - HTTP plumbing

    private func makeRequest(
        method: String,
        path: String,
        query: [URLQueryItem] = [],
    ) async throws -> URLRequest {
        var components = URLComponents(
            url: baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false,
        )
        if !query.isEmpty { components?.queryItems = query }
        guard let url = components?.url else {
            throw APIError.badRequest(message: "Couldn't assemble request URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token = await tokenProvider() {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func sendJSON<Body: Encodable, Response: Decodable>(
        method: String,
        path: String,
        body: Body,
    ) async throws -> Response {
        var request = try await makeRequest(method: method, path: path)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        return try await sendRequest(request)
    }

    private func sendNoBody<Response: Decodable>(
        method: String,
        path: String,
        query: [URLQueryItem] = [],
    ) async throws -> Response {
        let request = try await makeRequest(method: method, path: path, query: query)
        return try await sendRequest(request)
    }

    private func sendJSONVoid<Body: Encodable>(
        method: String,
        path: String,
        body: Body,
    ) async throws {
        var request = try await makeRequest(method: method, path: path)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try encoder.encode(body)
        let (data, response) = try await runDataTask(request)
        try mapStatus(response: response, data: data)
    }

    private func sendNoBodyVoid(
        method: String,
        path: String,
        query: [URLQueryItem] = [],
    ) async throws {
        let request = try await makeRequest(method: method, path: path, query: query)
        let (data, response) = try await runDataTask(request)
        try mapStatus(response: response, data: data)
    }

    private func sendRequest<Response: Decodable>(_ request: URLRequest) async throws -> Response {
        let (data, response) = try await runDataTask(request)
        try mapStatus(response: response, data: data)
        do {
            return try decoder.decode(Response.self, from: data)
        } catch {
            #if DEBUG
            if let body = String(data: data, encoding: .utf8) {
                print("[NemaraAPIClient] decode failure for \(Response.self): \(error)")
                print("[NemaraAPIClient] response body: \(body)")
            }
            #endif
            throw APIError.decoding(underlying: error.localizedDescription)
        }
    }

    private func runDataTask(_ request: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: request)
        } catch let urlError as URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .timedOut:
                throw APIError.offline
            default:
                throw APIError.other(message: urlError.localizedDescription)
            }
        } catch {
            throw APIError.other(message: error.localizedDescription)
        }
    }

    /// FastAPI emits two error shapes:
    /// - Simple `{"detail": "code_or_message"}` for HTTPException paths.
    /// - `{"detail": [{loc, msg, type}, …]}` for Pydantic 422 validation.
    /// We try both and fall back to a generic message.
    private func mapStatus(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.other(message: "Non-HTTP response.")
        }
        if (200..<300).contains(http.statusCode) { return }

        let simple = (try? decoder.decode(SimpleDetail.self, from: data))?.detail
        let validation = (try? decoder.decode(ValidationEnvelope.self, from: data))?.detail

        #if DEBUG
        if let body = String(data: data, encoding: .utf8), !body.isEmpty {
            print("[NemaraAPIClient] HTTP \(http.statusCode) body: \(body)")
        }
        #endif

        switch http.statusCode {
        case 400:
            throw APIError.badRequest(message: simple ?? "Bad request.")
        case 401:
            throw APIError.unauthorized
        case 403:
            throw APIError.forbidden
        case 404:
            throw APIError.notFound
        case 409:
            throw APIError.conflict(reason: simple ?? "conflict")
        case 422:
            throw APIError.badRequest(message: formatValidation(validation) ?? "Request failed validation (422).")
        case 500..<600:
            throw APIError.serverError(code: nil, message: simple)
        default:
            throw APIError.other(message: simple ?? "Request failed (\(http.statusCode)).")
        }
    }

    private func formatValidation(_ items: [ValidationItem]?) -> String? {
        guard let items, !items.isEmpty else { return nil }
        let parts = items.map { item -> String in
            let loc = (item.loc ?? []).joined(separator: ".")
            let msg = item.msg ?? "invalid"
            return loc.isEmpty ? msg : "\(loc): \(msg)"
        }
        return "Validation failed — \(parts.joined(separator: "; "))"
    }
}

// MARK: - FastAPI error envelopes

private struct SimpleDetail: Decodable { let detail: String? }
private struct ValidationItem: Decodable { let loc: [String]?; let msg: String?; let type: String? }
private struct ValidationEnvelope: Decodable { let detail: [ValidationItem]? }

// MARK: - Supabase Realtime

extension NemaraAPIClient {

    /// Open one channel per replicated table. The backend's
    /// `supabase_realtime` publication broadcasts INSERT/UPDATE/DELETE
    /// for `patients`, `cameras`, `detectors`, `events`. RLS policies
    /// filter per-caregiver server-side, so each client only receives
    /// rows it's already authorized to read.
    fileprivate func openRealtimeChannels() async {
        await subscribe(table: "patients", handler: handlePatientChange)
        await subscribe(table: "cameras", handler: handleCameraChange)
        await subscribe(table: "detectors", handler: handleDetectorChange)
        await subscribe(table: "events", handler: handleEventChange)
    }

    private func subscribe(
        table: String,
        handler: @escaping @MainActor (AnyAction) -> Void,
    ) async {
        let channel = supabase.realtimeV2.channel("nemara:\(table)")
        let stream = channel.postgresChange(AnyAction.self, table: table)
        let task = Task { @MainActor [weak self] in
            for await action in stream {
                guard self != nil else { break }
                #if DEBUG
                let kind: String = {
                    switch action {
                    case .insert: return "INSERT"
                    case .update: return "UPDATE"
                    case .delete: return "DELETE"
                    }
                }()
                print("[Realtime] \(table) \(kind)")
                #endif
                handler(action)
            }
        }
        streamTasks.append(task)
        channels.append(channel)
        do {
            try await channel.subscribeWithError()
            #if DEBUG
            print("[Realtime] subscribed to \(table)")
            #endif
        } catch {
            #if DEBUG
            print("[NemaraAPIClient] Realtime subscribe failed for \(table): \(error)")
            #endif
        }
    }

    // MARK: - Per-table handlers

    private func handlePatientChange(_ action: AnyAction) {
        let dec = NemaraJSON.decoder()
        switch action {
        case .insert(let a):
            guard let p = try? a.decodeRecord(as: Patient.self, decoder: dec) else { return }
            if !patients.contains(where: { $0.id == p.id }) {
                patients.append(p)
            }
        case .update(let a):
            guard let p = try? a.decodeRecord(as: Patient.self, decoder: dec) else { return }
            if let idx = patients.firstIndex(where: { $0.id == p.id }) {
                patients[idx] = p
            } else {
                patients.append(p)
            }
        case .delete(let a):
            guard let id = uuid(from: a.oldRecord["id"]) else { return }
            patients.removeAll { $0.id == id }
            camerasByPatient.removeValue(forKey: id)
            detectorsByPatient.removeValue(forKey: id)
            eventsByPatient.removeValue(forKey: id)
        }
    }

    private func handleCameraChange(_ action: AnyAction) {
        let dec = NemaraJSON.decoder()
        switch action {
        case .insert(let a):
            guard let cam = try? a.decodeRecord(as: Camera.self, decoder: dec) else { return }
            var arr = camerasByPatient[cam.patientId] ?? []
            if !arr.contains(where: { $0.id == cam.id }) { arr.append(cam) }
            camerasByPatient[cam.patientId] = arr.sorted { $0.displayId < $1.displayId }
        case .update(let a):
            guard let cam = try? a.decodeRecord(as: Camera.self, decoder: dec) else { return }
            var arr = camerasByPatient[cam.patientId] ?? []
            if let idx = arr.firstIndex(where: { $0.id == cam.id }) {
                arr[idx] = cam
            } else {
                arr.append(cam)
            }
            camerasByPatient[cam.patientId] = arr.sorted { $0.displayId < $1.displayId }
        case .delete(let a):
            guard let id = uuid(from: a.oldRecord["id"]) else { return }
            for (pid, arr) in camerasByPatient {
                if let idx = arr.firstIndex(where: { $0.id == id }) {
                    camerasByPatient[pid]?.remove(at: idx)
                    return
                }
            }
        }
    }

    private func handleDetectorChange(_ action: AnyAction) {
        let dec = NemaraJSON.decoder()
        switch action {
        case .insert(let a):
            guard let d = try? a.decodeRecord(as: Detector.self, decoder: dec) else { return }
            if detectorsByPatient[d.patientId]?.contains(where: { $0.id == d.id }) != true {
                detectorsByPatient[d.patientId, default: []].append(d)
            }
        case .update(let a):
            guard let d = try? a.decodeRecord(as: Detector.self, decoder: dec) else { return }
            var arr = detectorsByPatient[d.patientId] ?? []
            if let idx = arr.firstIndex(where: { $0.id == d.id }) {
                arr[idx] = d
            } else {
                arr.append(d)
            }
            detectorsByPatient[d.patientId] = arr
        case .delete(let a):
            guard let id = uuid(from: a.oldRecord["id"]) else { return }
            for (pid, arr) in detectorsByPatient {
                if let idx = arr.firstIndex(where: { $0.id == id }) {
                    detectorsByPatient[pid]?.remove(at: idx)
                    return
                }
            }
        }
    }

    private func handleEventChange(_ action: AnyAction) {
        let dec = NemaraJSON.decoder()
        switch action {
        case .insert(let a):
            guard let e = try? a.decodeRecord(as: DetectionEvent.self, decoder: dec) else { return }
            var arr = eventsByPatient[e.patientId] ?? []
            if !arr.contains(where: { $0.id == e.id }) {
                arr.insert(e, at: 0)  // newest first matches the GET-list sort
            }
            eventsByPatient[e.patientId] = arr
        case .update(let a):
            guard let e = try? a.decodeRecord(as: DetectionEvent.self, decoder: dec) else { return }
            var arr = eventsByPatient[e.patientId] ?? []
            if let idx = arr.firstIndex(where: { $0.id == e.id }) {
                arr[idx] = e
            } else {
                arr.insert(e, at: 0)
            }
            eventsByPatient[e.patientId] = arr
        case .delete(let a):
            guard let id = uuid(from: a.oldRecord["id"]) else { return }
            for (pid, arr) in eventsByPatient {
                if let idx = arr.firstIndex(where: { $0.id == id }) {
                    eventsByPatient[pid]?.remove(at: idx)
                    return
                }
            }
        }
    }

    private func uuid(from value: AnyJSON?) -> UUID? {
        guard let raw = value?.stringValue else { return nil }
        return UUID(uuidString: raw)
    }
}
