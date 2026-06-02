import PhotosUI
import SwiftUI
import UIKit

/// "Just page 1" of the patient onboarding flow — the basic profile.
/// Presented as a sheet from Roster's `+` and EmptyRoster's CTA.
struct NewPatientView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var fullName = ""
    // Required, no silent default — the caregiver must pick a date (it also
    // drives which preset detectors get seeded: under 18 = child set).
    @State private var dateOfBirth: Date?
    @State private var showDOBSheet = false
    @State private var dobMonth = 1
    @State private var dobDay = 1
    @State private var dobYear = Calendar.current.component(.year, from: Date()) - 70
    @State private var gender = "Female"
    @State private var relation: Patient.Relation = .parent

    // Photo is picked here but uploaded only AFTER createPatient
    // returns the new patient_id — the upload endpoint is keyed by
    // patient_id and we don't have one until then.
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var pickedPhotoJPEG: Data?
    @State private var pickedPhotoPreview: UIImage?
    @State private var isLoadingPhoto = false

    // Submit state. Failures surface inline so the caregiver knows the
    // patient wasn't actually created.
    @State private var isSubmitting = false
    @State private var submitError: String?

    // After Step 1 (profile) submit succeeds we present the post-create
    // flow: a facial-detection consent screen, then (if they proceed) the
    // face-enrollment capture step. Set to the new patient_id on success.
    @State private var createdPatientId: UUID?

    private var canSubmit: Bool {
        !fullName.trimmingCharacters(in: .whitespaces).isEmpty
            && dateOfBirth != nil
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        intro
                        NemaraField("Name", text: $fullName, placeholder: "Margaret O'Brien",
                                    autocapitalization: .words)
                        dateOfBirthAndGender
                        relationshipPicker
                        photoRow
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                }

                footer
            }
            .background(NemaraColor.paper)
            .fullScreenCover(
                isPresented: Binding(
                    get: { createdPatientId != nil },
                    set: { if !$0 { createdPatientId = nil } },
                ),
            ) {
                if let pid = createdPatientId {
                    PostCreateEnrollmentFlow(patientId: pid) {
                        createdPatientId = nil
                        dismiss()
                    }
                    .environment(env)
                }
            }
            .sheet(isPresented: $showDOBSheet) { dobSheet }
        }
    }

    // MARK: - sections

    private var header: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(NemaraColor.ink)
            }
            .buttonStyle(.plain)
            Spacer()
            Text("New patient")
                .font(NemaraFont.bodyLarge.weight(.semibold))
                .foregroundStyle(NemaraColor.ink)
                .kerning(-0.2)
            Spacer()
            // invisible spacer to balance the X
            Image(systemName: "xmark").opacity(0)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(NemaraColor.paper)
        .overlay(NemaraColor.line.frame(height: 1), alignment: .bottom)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 6) {
            NemaraEyebrow("BASIC PROFILE", color: NemaraColor.terra)
            Text("Tell us about your patient.")
                .font(NemaraFont.title1)
                .foregroundStyle(NemaraColor.ink)
                .kerning(-0.8)
                .fixedSize(horizontal: false, vertical: true)
            Text("Just the basics. Their feeds and events appear here automatically once you're added as a caregiver.")
                .font(NemaraFont.bodySmall)
                .foregroundStyle(NemaraColor.ink2)
                .lineSpacing(2)
                .padding(.top, 2)
        }
    }

    private var dateOfBirthAndGender: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                NemaraEyebrow("DATE OF BIRTH")
                Button {
                    if let dob = dateOfBirth {
                        let c = Calendar.current.dateComponents([.day, .month, .year], from: dob)
                        dobMonth = c.month ?? dobMonth
                        dobDay = c.day ?? dobDay
                        dobYear = c.year ?? dobYear
                    }
                    showDOBSheet = true
                } label: {
                    HStack {
                        Text(dateOfBirth.map(Self.dobFormatter.string(from:)) ?? "Select")
                            .font(NemaraFont.bodyLarge)
                            .foregroundStyle(dateOfBirth == nil ? NemaraColor.ink3 : NemaraColor.ink)
                        Spacer()
                        Image(systemName: "calendar")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(NemaraColor.ink3)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NemaraColor.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous)
                            .strokeBorder(NemaraColor.line, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous))
                }
                .buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 6) {
                NemaraEyebrow("GENDER")
                Menu {
                    ForEach(["Female", "Male", "Non-binary", "Prefer not to say"], id: \.self) { g in
                        Button(g) { gender = g }
                    }
                } label: {
                    HStack {
                        Text(gender)
                            .font(NemaraFont.bodyLarge)
                            .foregroundStyle(NemaraColor.ink)
                        Spacer()
                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(NemaraColor.ink3)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 11)
                    .background(NemaraColor.card)
                    .overlay(
                        RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous)
                            .strokeBorder(NemaraColor.line, lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous))
                }
                .tint(NemaraColor.ink)
            }
        }
    }

    private var relationshipPicker: some View {
        VStack(alignment: .leading, spacing: 8) {
            NemaraEyebrow("YOUR RELATIONSHIP")
            FlexibleGrid(spacing: 6) {
                ForEach(Patient.Relation.allCases, id: \.self) { rel in
                    let on = rel == relation
                    Button { relation = rel } label: {
                        Text(rel.displayName)
                            .font(NemaraFont.bodyMedium)
                            .foregroundStyle(on ? NemaraColor.terraInk : NemaraColor.ink2)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(on ? NemaraColor.terra : .clear)
                            .overlay(
                                Capsule().strokeBorder(on ? NemaraColor.terra : NemaraColor.line, lineWidth: 1)
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var photoRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            NemaraEyebrow("A PHOTO (OPTIONAL)")
            HStack(spacing: 12) {
                avatarOrPickedPreview
                PhotosPicker(
                    selection: $selectedPhotoItem,
                    matching: .images,
                    photoLibrary: .shared(),
                ) {
                    HStack {
                        Spacer()
                        if isLoadingPhoto {
                            ProgressView()
                        } else {
                            Text(pickedPhotoJPEG == nil ? "+ Upload photo" : "Change photo")
                                .font(NemaraFont.bodySmall)
                                .foregroundStyle(NemaraColor.ink3)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 12)
                    .background(NemaraColor.card.opacity(0))
                    .overlay(
                        RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous)
                            .strokeBorder(
                                NemaraColor.line,
                                style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]),
                            )
                    )
                }
                .buttonStyle(.plain)
                .disabled(isSubmitting)
            }
        }
        .onChange(of: selectedPhotoItem) { _, newItem in
            guard let newItem else { return }
            Task { await loadPickedPhoto(newItem) }
        }
    }

    @ViewBuilder
    private var avatarOrPickedPreview: some View {
        if let preview = pickedPhotoPreview {
            Image(uiImage: preview)
                .resizable()
                .scaledToFill()
                .frame(width: 68, height: 68)
                .clipShape(Circle())
        } else {
            NemaraAvatar(
                letter: String(fullName.first ?? "?"),
                size: 68,
            )
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if let submitError {
                Text(submitError)
                    .font(NemaraFont.bodySmall)
                    .foregroundStyle(NemaraColor.terra)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
            }
            HStack {
                NemaraButton(
                    isSubmitting ? "Adding…" : "Add patient",
                    variant: .primary, block: true, action: submit,
                )
                .disabled(!canSubmit || isSubmitting)
                .opacity((canSubmit && !isSubmitting) ? 1 : 0.5)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(NemaraColor.paper)
        .overlay(NemaraColor.line.frame(height: 1), alignment: .top)
    }

    // MARK: - actions

    private func submit() {
        // Preferred name is no longer collected — mirror it from the name.
        // Cap at the backend's 80-char `preferred_name` limit.
        let name = fullName.trimmingCharacters(in: .whitespaces)
        let body = CreatePatientRequest(
            fullName: name,
            preferredName: String(name.prefix(80)),
            relation: relation,
            dateOfBirth: dateOfBirth,
            gender: gender.isEmpty ? nil : gender,
            homeAddress: nil,
        )

        Task {
            isSubmitting = true
            submitError = nil
            defer { isSubmitting = false }
            do {
                let patient = try await env.api.createPatient(body)
                // Photo is best-effort; the patient row already exists,
                // so a photo upload failure shouldn't roll back creation.
                if let jpeg = pickedPhotoJPEG {
                    do {
                        _ = try await env.api.uploadPatientPhoto(
                            patient.id, imageData: jpeg, contentType: "image/jpeg",
                        )
                    } catch {
                        NSLog("[NewPatient] photo upload failed: %@", "\(error)")
                    }
                }
                // Step 2: present the facial-detection consent flow, which
                // (on Proceed) leads into face enrollment.
                createdPatientId = patient.id
            } catch {
                submitError = error.localizedDescription
            }
        }
    }

    private func loadPickedPhoto(_ item: PhotosPickerItem) async {
        isLoadingPhoto = true
        defer { isLoadingPhoto = false }
        guard let raw = try? await item.loadTransferable(type: Data.self) else {
            submitError = "Couldn't read the selected photo."
            return
        }
        guard let jpeg = Self.downsampledJPEG(from: raw, maxDimension: 1024, quality: 0.8) else {
            submitError = "That image format isn't supported."
            return
        }
        pickedPhotoJPEG = jpeg
        pickedPhotoPreview = UIImage(data: jpeg)
    }

    /// Same downsample logic as PatientSettingsView — keep them in
    /// sync if either changes. 1024px longest edge at q=0.8 lands
    /// well under the backend's 1 MiB cap for any reasonable input.
    private static func downsampledJPEG(
        from data: Data, maxDimension: CGFloat, quality: CGFloat,
    ) -> Data? {
        guard let image = UIImage(data: data) else { return nil }
        let w = image.size.width, h = image.size.height
        let longest = max(w, h)
        let scale: CGFloat = longest > maxDimension ? maxDimension / longest : 1.0
        let target = CGSize(width: w * scale, height: h * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: target, format: format)
        let resized = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
        return resized.jpegData(compressionQuality: quality)
    }

    private static let dobFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("yMMMMd")  // e.g. "March 1, 1955"
        return f
    }()

    private static let monthSymbols: [String] = DateFormatter().monthSymbols

    /// Days available in the currently-selected month/year — handles
    /// 28/29/30/31 and leap years so the day wheel never offers an
    /// invalid date like Feb 30.
    private func daysInSelectedMonth() -> Int {
        var comps = DateComponents()
        comps.year = dobYear
        comps.month = dobMonth
        if let date = Calendar.current.date(from: comps),
           let range = Calendar.current.range(of: .day, in: .month, for: date) {
            return range.count
        }
        return 31
    }

    /// If the selected month/year shrinks the valid day range (e.g.
    /// switching to February), pull an out-of-range day back to the last
    /// valid day so "Done" never builds an invalid date.
    private func clampDOBDay() {
        let maxDay = daysInSelectedMonth()
        if dobDay > maxDay { dobDay = maxDay }
    }

    private var dobSheet: some View {
        let currentYear = Calendar.current.component(.year, from: Date())
        let dayCount = daysInSelectedMonth()
        return NavigationStack {
            HStack(spacing: 0) {
                Picker("Month", selection: $dobMonth) {
                    ForEach(1...12, id: \.self) { m in
                        Text(Self.monthSymbols[m - 1]).tag(m)
                    }
                }
                .pickerStyle(.wheel)
                Picker("Day", selection: $dobDay) {
                    ForEach(1...dayCount, id: \.self) { d in
                        Text(String(d)).tag(d)
                    }
                }
                .pickerStyle(.wheel)
                Picker("Year", selection: $dobYear) {
                    ForEach(Array(1920...currentYear), id: \.self) { y in
                        Text(String(y)).tag(y)
                    }
                }
                .pickerStyle(.wheel)
            }
            .tint(NemaraColor.terra)
            .onChange(of: dobMonth) { _, _ in clampDOBDay() }
            .onChange(of: dobYear) { _, _ in clampDOBDay() }
            .padding()
            .navigationTitle("Date of birth")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showDOBSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        if let d = Calendar.current.date(
                            from: DateComponents(year: dobYear, month: dobMonth, day: dobDay)
                        ) {
                            dateOfBirth = d
                        }
                        showDOBSheet = false
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}


// MARK: - Post-create facial-detection consent flow

/// Local persistence for the "Don't ask me again" choice on the consent
/// screen, per patient. The reminder banner that would read this is a
/// future addition; for now both "Maybe later" and "Don't ask me again"
/// simply dismiss — the choice is just recorded for later.
enum FaceConsentPrefs {
    private static func key(_ patientId: UUID) -> String {
        "faceConsentDismissed.\(patientId.uuidString)"
    }
    static func isDismissed(_ patientId: UUID) -> Bool {
        UserDefaults.standard.bool(forKey: key(patientId))
    }
    static func setDismissed(_ patientId: UUID) {
        UserDefaults.standard.set(true, forKey: key(patientId))
    }
}

/// Shown right after a patient is created: the facial-detection consent
/// screen, then the face-enrollment capture step if they proceed. Swaps
/// content within one cover so there's no dismiss/re-present flash.
private struct PostCreateEnrollmentFlow: View {
    let patientId: UUID
    let onFinish: () -> Void
    @Environment(AppEnvironment.self) private var env
    @State private var showEnrollment = false

    var body: some View {
        if showEnrollment {
            FaceEnrollmentStepView(patientId: patientId) { onFinish() }
                .environment(env)
        } else {
            FaceDetectionConsentView(
                onProceed: { showEnrollment = true },
                onMaybeLater: onFinish,
                onDontAskAgain: {
                    FaceConsentPrefs.setDismissed(patientId)
                    onFinish()
                }
            )
        }
    }
}

/// "Would you like to add facial detection?" — the consent screen.
private struct FaceDetectionConsentView: View {
    let onProceed: () -> Void
    let onMaybeLater: () -> Void
    let onDontAskAgain: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(alignment: .leading, spacing: 16) {
                ZStack {
                    Circle().fill(NemaraColor.terraSoft).frame(width: 64, height: 64)
                    Image(systemName: "faceid")
                        .font(.system(size: 28, weight: .semibold))
                        .foregroundStyle(NemaraColor.terra)
                }
                Text("Would you like to add facial detection?")
                    .font(NemaraFont.title1)
                    .foregroundStyle(NemaraColor.ink)
                    .kerning(-0.6)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Adding facial detection lets Memoria be more accurate, so alerts are more timely and consistent.")
                    .font(NemaraFont.body)
                    .foregroundStyle(NemaraColor.ink2)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            Spacer()
            VStack(spacing: 10) {
                NemaraButton("Proceed", variant: .primary, block: true, action: onProceed)
                NemaraButton("Maybe later", variant: .secondary, block: true, action: onMaybeLater)
                NemaraButton("Don't ask me again", variant: .ghost, block: true, action: onDontAskAgain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(NemaraColor.paper)
    }
}

/// Tiny flow layout for the relationship chips. SwiftUI's stock
/// `Layout` would do the same, but this keeps the dep footprint small.
struct FlexibleGrid<Content: View>: View {
    let spacing: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        FlowLayout(spacing: spacing) {
            content()
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxW = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0
        var maxXReached: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > maxW {
                x = 0
                y += rowH + spacing
                rowH = 0
            }
            x += sz.width + spacing
            maxXReached = max(maxXReached, x)
            rowH = max(rowH, sz.height)
        }
        return CGSize(width: maxXReached, height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX, y: CGFloat = bounds.minY, rowH: CGFloat = 0
        for s in subviews {
            let sz = s.sizeThatFits(.unspecified)
            if x + sz.width > bounds.maxX {
                x = bounds.minX
                y += rowH + spacing
                rowH = 0
            }
            s.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(sz))
            x += sz.width + spacing
            rowH = max(rowH, sz.height)
        }
    }
}

#if DEBUG
#Preview {
    NewPatientView()
        .environment(AppEnvironment.preview())
}
#endif
