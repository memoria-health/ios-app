import PhotosUI
import SwiftUI

/// Edit the patient profile — everything the add-patient first page
/// collects (name, goes-by, date of birth, gender, relationship) plus
/// the photo, in one labeled form. Replaces the 2026-08-17 inline
/// card-edit attempt, which rendered two unlabeled name fields and
/// scattered Save/Cancel around the card (Aryaman: "looks really bad").
/// Field styling mirrors NewPatientView so add and edit feel like the
/// same form. Country is deliberately absent: it pins data residency
/// and is not PATCHable.
struct EditPatientSheet: View {
    let patientId: UUID
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var fullName = ""
    @State private var preferredName = ""
    @State private var gender = ""
    @State private var relation: Patient.Relation = .other
    @State private var dateOfBirth: Date?
    @State private var showDOBWheels = false
    @State private var dobMonth = 1
    @State private var dobDay = 1
    @State private var dobYear = 1950

    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var isUploadingPhoto = false
    @State private var isSaving = false
    @State private var errorText: String?

    private var patient: Patient? {
        env.api.patients.first(where: { $0.id == patientId })
    }

    private static let dobFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    photoRow
                    NemaraField("Name", text: $fullName,
                                placeholder: "Margaret O'Brien",
                                autocapitalization: .words)
                    NemaraField("Goes by", text: $preferredName,
                                placeholder: "Maggie",
                                autocapitalization: .words)
                    dobAndGender
                    relationshipRow
                    if let errorText {
                        Text(errorText)
                            .font(NemaraFont.caption)
                            .foregroundStyle(NemaraColor.terra)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
            .background(NemaraColor.paper)
            .navigationTitle("Edit profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(isSaving)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isSaving ? "Saving…" : "Save") {
                        Task { await save() }
                    }
                    .disabled(
                        isSaving
                        || fullName.trimmingCharacters(in: .whitespaces).isEmpty
                    )
                }
            }
            .onAppear(perform: seed)
            .onChange(of: selectedPhotoItem) { _, newItem in
                guard let newItem else { return }
                Task { await uploadPickedPhoto(newItem) }
            }
        }
    }

    // MARK: - rows

    private var photoRow: some View {
        HStack(spacing: 14) {
            if let p = patient {
                PatientAvatar(patient: p, size: 64)
            } else {
                NemaraAvatar(letter: "?", size: 64)
            }
            PhotosPicker(
                selection: $selectedPhotoItem,
                matching: .images,
                photoLibrary: .shared(),
            ) {
                Text(isUploadingPhoto ? "Uploading…" : "Change photo")
                    .font(NemaraFont.bodySmallStrong)
                    .foregroundStyle(NemaraColor.action)
            }
            .disabled(isUploadingPhoto)
            if patient?.photoStorageKey != nil {
                Button("Remove") {
                    Task { await removePhoto() }
                }
                .font(NemaraFont.bodySmallStrong)
                .foregroundStyle(NemaraColor.terra)
                .disabled(isUploadingPhoto)
            }
            Spacer()
        }
    }

    private var dobAndGender: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 6) {
                NemaraEyebrow("DATE OF BIRTH")
                Button {
                    if let dob = dateOfBirth {
                        let c = Calendar.current.dateComponents(
                            [.day, .month, .year], from: dob)
                        dobMonth = c.month ?? dobMonth
                        dobDay = c.day ?? dobDay
                        dobYear = c.year ?? dobYear
                    }
                    withAnimation { showDOBWheels.toggle() }
                } label: {
                    boxedLabel(
                        dateOfBirth.map(Self.dobFormatter.string(from:)) ?? "Select",
                        dimmed: dateOfBirth == nil, trailingIcon: "calendar",
                    )
                }
                .buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 6) {
                NemaraEyebrow("GENDER")
                Menu {
                    ForEach(["Female", "Male", "Non-binary", "Prefer not to say"],
                            id: \.self) { g in
                        Button(g) { gender = g }
                    }
                } label: {
                    boxedLabel(gender.isEmpty ? "Select" : gender,
                               dimmed: gender.isEmpty,
                               trailingIcon: "chevron.up.chevron.down")
                }
            }
        }
        .overlay(alignment: .bottom) { EmptyView() }
        .background(alignment: .bottom) { EmptyView() }
        .padding(.bottom, showDOBWheels ? 0 : 0)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if showDOBWheels { dobWheels }
        }
    }

    private var dobWheels: some View {
        HStack(spacing: 0) {
            Picker("Month", selection: $dobMonth) {
                ForEach(1...12, id: \.self) {
                    Text(Calendar.current.shortMonthSymbols[$0 - 1]).tag($0)
                }
            }
            Picker("Day", selection: $dobDay) {
                ForEach(1...31, id: \.self) { Text("\($0)").tag($0) }
            }
            Picker("Year", selection: $dobYear) {
                ForEach((1920...Calendar.current.component(.year, from: .now)).reversed(),
                        id: \.self) { Text(String($0)).tag($0) }
            }
        }
        .pickerStyle(.wheel)
        .frame(height: 130)
        .onChange(of: [dobMonth, dobDay, dobYear]) { _, _ in
            var c = DateComponents()
            c.year = dobYear; c.month = dobMonth; c.day = dobDay
            dateOfBirth = Calendar.current.date(from: c)
        }
    }

    private var relationshipRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            NemaraEyebrow("RELATIONSHIP")
            Menu {
                ForEach(Patient.Relation.allCases, id: \.self) { rel in
                    Button(rel.displayName) { relation = rel }
                }
            } label: {
                boxedLabel(relation.displayName, dimmed: false,
                           trailingIcon: "chevron.up.chevron.down")
            }
        }
    }

    private func boxedLabel(
        _ text: String, dimmed: Bool, trailingIcon: String,
    ) -> some View {
        HStack {
            Text(text)
                .font(NemaraFont.bodyLarge)
                .foregroundStyle(dimmed ? NemaraColor.ink3 : NemaraColor.ink)
            Spacer()
            Image(systemName: trailingIcon)
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

    // MARK: - actions

    private func seed() {
        guard let p = patient else { return }
        fullName = p.fullName
        preferredName = p.preferredName
        gender = p.gender ?? ""
        relation = p.relation
        dateOfBirth = p.dateOfBirth
    }

    private func save() async {
        guard let p = patient else { return }
        isSaving = true
        defer { isSaving = false }
        errorText = nil
        do {
            let full = fullName.trimmingCharacters(in: .whitespaces)
            let preferred = preferredName.trimmingCharacters(in: .whitespaces)
            _ = try await env.api.updatePatient(p.id, UpdatePatientRequest(
                fullName: full,
                preferredName: preferred.isEmpty ? full : preferred,
                dateOfBirth: dateOfBirth,
                gender: gender.isEmpty ? nil : gender,
                relation: relation,
            ))
            dismiss()
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func uploadPickedPhoto(_ item: PhotosPickerItem) async {
        guard let p = patient else { return }
        isUploadingPhoto = true
        errorText = nil
        defer { isUploadingPhoto = false; selectedPhotoItem = nil }
        do {
            guard let raw = try await item.loadTransferable(type: Data.self) else {
                errorText = "Couldn't read the selected photo."
                return
            }
            guard let jpeg = PatientSettingsView.downsampledJPEG(
                from: raw, maxDimension: 1024, quality: 0.8) else {
                errorText = "That image format isn't supported."
                return
            }
            try await env.api.uploadPatientPhoto(
                p.id, imageData: jpeg, contentType: "image/jpeg",
            )
        } catch {
            errorText = error.localizedDescription
        }
    }

    private func removePhoto() async {
        guard let p = patient else { return }
        errorText = nil
        do {
            try await env.api.deletePatientPhoto(p.id)
        } catch {
            errorText = error.localizedDescription
        }
    }
}
