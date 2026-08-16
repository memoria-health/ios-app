import PhotosUI
import SwiftUI

/// Combined feedback / share / contact screen. Pushed from
/// PatientSettings's "Feedback & support" row. Self-contained — no
/// nested navigation.
struct FeedbackView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var env
    @State private var rating: Int = 0
    @State private var whatsLoved: String = ""
    @State private var whatsNotWorking: String = ""
    @State private var isSubmitting = false
    @State private var submitted = false
    @State private var submitError: String?

    // Screenshot attachments. `pickerItems` is the raw PhotosUI selection;
    // `attachments` is the decoded + JPEG-compressed result we actually
    // upload (and thumbnail). Capped at `maxAttachments` to match the
    // backend's per-request limit.
    @State private var pickerItems: [PhotosPickerItem] = []
    @State private var attachments: [FeedbackAttachment] = []
    // Decoding + JPEG compression isn't instant, so while it runs we show
    // placeholder tiles (one per just-picked item) with a spinner — the
    // user sees their pick registered immediately instead of a dead pause.
    @State private var isLoadingAttachments = false
    private let maxAttachments = 4

    // The primary field — "what's not working / could be improved" — is the
    // only required one; the rest (what you like, the rating) are optional.
    private var canSubmit: Bool {
        !whatsNotWorking.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @MainActor
    private func submit() async {
        guard canSubmit, !isSubmitting else { return }
        isSubmitting = true
        submitError = nil
        defer { isSubmitting = false }
        func nonBlank(_ s: String) -> String? {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        let encoded = attachments.map { $0.jpeg.base64EncodedString() }
        do {
            _ = try await env.api.submitFeedback(
                rating: rating == 0 ? nil : rating,
                whatsWorking: nonBlank(whatsLoved),
                whatsFrustrating: nonBlank(whatsNotWorking),
                category: nil,
                attachments: encoded.isEmpty ? nil : encoded,
            )
            withAnimation(.spring(response: 0.4, dampingFraction: 0.8)) { submitted = true }
        } catch {
            submitError = "Couldn't send feedback. \(error.localizedDescription)"
        }
    }

    /// Decode the PhotosUI selection into JPEG-compressed attachments,
    /// re-encoding large images down so a screenshot stays well under the
    /// backend's per-image cap. Best-effort: an item that fails to load is
    /// silently dropped rather than failing the whole selection.
    @MainActor
    private func loadAttachments(from items: [PhotosPickerItem]) async {
        guard !items.isEmpty else {
            withAnimation(.easeInOut(duration: 0.2)) { attachments = [] }
            return
        }
        isLoadingAttachments = true
        var loaded: [FeedbackAttachment] = []
        for item in items.prefix(maxAttachments) {
            guard
                let data = try? await item.loadTransferable(type: Data.self),
                let image = UIImage(data: data),
                let jpeg = Self.compressedJPEG(image)
            else { continue }
            loaded.append(FeedbackAttachment(image: image, jpeg: jpeg))
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            attachments = loaded
            isLoadingAttachments = false
        }
    }

    /// Downscale to a sane max dimension, then JPEG-encode. Keeps an
    /// iPhone screenshot comfortably under the ~3 MB-image backend limit.
    private static func compressedJPEG(_ image: UIImage) -> Data? {
        let maxDimension: CGFloat = 1600
        let longest = max(image.size.width, image.size.height)
        let scaled: UIImage
        if longest > maxDimension {
            let factor = maxDimension / longest
            let newSize = CGSize(width: image.size.width * factor,
                                 height: image.size.height * factor)
            let format = UIGraphicsImageRendererFormat.default()
            format.scale = 1
            scaled = UIGraphicsImageRenderer(size: newSize, format: format).image { _ in
                image.draw(in: CGRect(origin: .zero, size: newSize))
            }
        } else {
            scaled = image
        }
        return scaled.jpegData(compressionQuality: 0.6)
    }

    private func removeAttachment(_ attachment: FeedbackAttachment) {
        withAnimation(.easeInOut(duration: 0.2)) {
            attachments.removeAll { $0.id == attachment.id }
            pickerItems.removeAll()
        }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                foundersCard
                feedbackForm
                Text("THANK YOU · MEMORIA v0.1")
                    .font(NemaraFont.eyebrow)
                    .tracking(0.5)
                    .foregroundStyle(NemaraColor.ink3)
                    .padding(.top, 4)
                    .padding(.bottom, 16)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(NemaraColor.paper)
        // Success haptic when the feedback lands — a clear "it went through"
        // signal beyond the visual confirmation.
        .sensoryFeedback(.success, trigger: submitted)
        // Decode the PhotosUI selection into compressed JPEGs we can upload.
        // Runs off the selection change; caps at maxAttachments defensively
        // even though the picker already limits selection.
        .onChange(of: pickerItems) { _, items in
            Task { await loadAttachments(from: items) }
        }
        .scrollDismissesKeyboard(.interactively)
        .dismissKeyboardOnTap()
        .navigationTitle("Feedback")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        // Pin the nav bar to paper. Otherwise iOS swaps to an opaque system
        // material (reads white in light mode) once content scrolls under the
        // bar — the same fix PatientShell applies to its tab bars.
        .toolbarBackground(NemaraColor.paper, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button { dismiss() } label: {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(NemaraColor.ink)
                }
            }
        }
    }

    private var foundersCard: some View {
        NemaraCard(tone: .terra, padding: 16, borderColor: .clear) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 12) {
                    NemaraMark(size: 42)
                    VStack(alignment: .leading, spacing: 4) {
                        NemaraEyebrow("FROM THE FOUNDERS", color: NemaraColor.terra)
                        Text("We read every message.")
                            .font(NemaraFont.title3)
                            .kerning(-0.3)
                            .foregroundStyle(NemaraColor.ink)
                    }
                    Spacer()
                }
                Text("Tell us how we can improve. We respond to all inquiries within 2 business days.")
                    .font(NemaraFont.bodySmall)
                    .foregroundStyle(NemaraColor.ink2)
                    .lineSpacing(5)
            }
        }
    }

    private var feedbackForm: some View {
        VStack(alignment: .leading, spacing: 8) {
            NemaraEyebrow("FEEDBACK")
            NemaraCard(padding: 14) {
                VStack(alignment: .leading, spacing: 16) {
                    notWorkingField
                    likeField
                    ratingScale
                    if !submitted {
                        screenshotsField
                    }
                    if submitted {
                        VStack(spacing: 10) {
                            ZStack {
                                Circle()
                                    .fill(NemaraColor.terraSoft)
                                    .frame(width: 56, height: 56)
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.system(size: 34, weight: .semibold))
                                    .foregroundStyle(NemaraColor.terra)
                            }
                            Text("Feedback sent")
                                .font(NemaraFont.title3)
                                .foregroundStyle(NemaraColor.ink)
                            Text("Thank you — we read every message and respond within 2 business days.")
                                .font(NemaraFont.bodySmall)
                                .foregroundStyle(NemaraColor.ink2)
                                .multilineTextAlignment(.center)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                            NemaraButton("Done", variant: .secondary, size: .md) { dismiss() }
                                .padding(.top, 2)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    } else {
                        if let submitError {
                            Text(submitError)
                                .font(NemaraFont.caption)
                                .foregroundStyle(NemaraColor.terra)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        NemaraButton(
                            isSubmitting ? "Sending…" : "Send feedback",
                            variant: .primary, size: .lg, block: true,
                            systemImage: "paperplane.fill",
                        ) {
                            Task { await submit() }
                        }
                        .disabled(isSubmitting || !canSubmit)
                        .opacity((isSubmitting || !canSubmit) ? 0.5 : 1)
                        .padding(.top, 6)
                    }
                }
            }
        }
    }

    private var ratingScale: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                NemaraEyebrow("HOW IS MEMORIA GOING?")
                Text("optional")
                    .font(NemaraFont.caption.italic())
                    .foregroundStyle(NemaraColor.ink3)
            }
            let palette: [Color] = [
                Color(red: 0xA0/255, green: 0x43/255, blue: 0x31/255),
                Color(red: 0xC2/255, green: 0x62/255, blue: 0x44/255),
                Color(red: 0xC6/255, green: 0x8A/255, blue: 0x3D/255),
                Color(red: 0x8A/255, green: 0x8E/255, blue: 0x3A/255),
                Color(red: 0x4A/255, green: 0x5D/255, blue: 0x3A/255),
            ]
            HStack(spacing: 4) {
                ForEach(1...5, id: \.self) { n in
                    Button { rating = n } label: {
                        Text("\(n)")
                            .font(NemaraFont.bodySmallStrong)
                            .foregroundStyle(n <= rating ? NemaraColor.terraInk : NemaraColor.ink3)
                            .frame(maxWidth: .infinity)
                            .frame(height: 36)
                            .background(n <= rating ? palette[n - 1] : .clear)
                            .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.sm, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(4)
            .background(NemaraColor.paperDim)
            .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous))
            HStack {
                Text("NOT GREAT").font(NemaraFont.monoSmall).foregroundStyle(NemaraColor.ink3)
                Spacer()
                Text("LOVE IT").font(NemaraFont.monoSmall).foregroundStyle(NemaraColor.ink3)
            }
        }
    }

    private var likeField: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                NemaraEyebrow("WHAT DO YOU LIKE ABOUT MEMORIA?")
                Text("optional")
                    .font(NemaraFont.caption.italic())
                    .foregroundStyle(NemaraColor.ink3)
            }
            ZStack(alignment: .topLeading) {
                if whatsLoved.isEmpty {
                    Text("What's landing well for you…")
                        .font(NemaraFont.bodySmall)
                        .foregroundStyle(NemaraColor.ink3)
                        .padding(12)
                }
                TextEditor(text: $whatsLoved)
                    .font(NemaraFont.bodySmall)
                    .foregroundStyle(NemaraColor.ink)
                    .scrollContentBackground(.hidden)
                    // Match notWorkingField — keep the caret aligned with the
                    // placeholder (see note there).
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .tint(NemaraColor.terra)
            }
            .frame(minHeight: 64)
            .background(NemaraColor.paperDim)
            .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous))
        }
    }

    private var notWorkingField: some View {
        VStack(alignment: .leading, spacing: 6) {
            NemaraEyebrow("WHAT'S NOT WORKING / COULD BE IMPROVED?")
            ZStack(alignment: .topLeading) {
                if whatsNotWorking.isEmpty {
                    Text("What should we fix or improve…")
                        .font(NemaraFont.bodySmall)
                        .foregroundStyle(NemaraColor.ink3)
                        .padding(12)
                }
                TextEditor(text: $whatsNotWorking)
                    .font(NemaraFont.bodySmall)
                    .foregroundStyle(NemaraColor.ink)
                    .scrollContentBackground(.hidden)
                    // Less vertical padding so the caret/first line lines up
                    // with the placeholder — TextEditor adds its own ~8pt top
                    // text-container inset on top of this, which was pushing the
                    // caret a few points below the placeholder text.
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .tint(NemaraColor.terra)
            }
            .frame(minHeight: 64)
            .background(NemaraColor.paperDim)
            .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.md, style: .continuous))
        }
    }

    private var screenshotsField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                NemaraEyebrow("SCREENSHOTS")
                Text("optional")
                    .font(NemaraFont.caption.italic())
                    .foregroundStyle(NemaraColor.ink3)
                Spacer()
                if isLoadingAttachments {
                    Text("Adding…")
                        .font(NemaraFont.monoSmall)
                        .foregroundStyle(NemaraColor.ink3)
                } else if !attachments.isEmpty {
                    Text("\(attachments.count)/\(maxAttachments)")
                        .font(NemaraFont.monoSmall)
                        .foregroundStyle(NemaraColor.ink3)
                }
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if isLoadingAttachments {
                        // Immediate feedback: one spinner tile per just-picked
                        // item, swapped for real thumbnails once decoding ends.
                        ForEach(0..<placeholderCount, id: \.self) { _ in
                            loadingTile
                        }
                    } else {
                        ForEach(attachments) { attachment in
                            thumbnail(attachment)
                        }
                        if attachments.count < maxAttachments {
                            addButton
                        }
                    }
                }
            }
        }
    }

    /// How many spinner placeholders to show mid-load — the count the user
    /// just picked, capped at the limit (≥1 so something always shows).
    private var placeholderCount: Int {
        max(1, min(pickerItems.count, maxAttachments))
    }

    private var loadingTile: some View {
        ProgressView()
            .tint(NemaraColor.ink3)
            .frame(width: 64, height: 64)
            .background(NemaraColor.paperDim)
            .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.sm, style: .continuous))
    }

    private var addButton: some View {
        PhotosPicker(
            selection: $pickerItems,
            maxSelectionCount: maxAttachments,
            matching: .images,
            photoLibrary: .shared(),
        ) {
            VStack(spacing: 4) {
                Image(systemName: "photo.badge.plus")
                    .font(.system(size: 18, weight: .regular))
                Text("Add")
                    .font(NemaraFont.caption)
            }
            .foregroundStyle(NemaraColor.ink3)
            .frame(width: 64, height: 64)
            .background(NemaraColor.paperDim)
            .overlay(
                RoundedRectangle(cornerRadius: NemaraRadius.sm, style: .continuous)
                    .strokeBorder(NemaraColor.line, style: StrokeStyle(lineWidth: 1, dash: [4, 3])),
            )
            .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func thumbnail(_ attachment: FeedbackAttachment) -> some View {
        Image(uiImage: attachment.image)
            .resizable()
            .scaledToFill()
            .frame(width: 64, height: 64)
            .clipShape(RoundedRectangle(cornerRadius: NemaraRadius.sm, style: .continuous))
            .overlay(alignment: .topTrailing) {
                Button { removeAttachment(attachment) } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundStyle(.white, .black.opacity(0.5))
                        .padding(3)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove screenshot")
            }
    }

}

/// One screenshot the caregiver attached to feedback: the decoded image
/// for the on-screen thumbnail, plus the JPEG bytes we base64-encode and
/// upload. `id` is per-pick so thumbnails diff/animate cleanly.
private struct FeedbackAttachment: Identifiable {
    let id = UUID()
    let image: UIImage
    let jpeg: Data
}

#if DEBUG
#Preview {
    NavigationStack { FeedbackView() }
        .environment(AppEnvironment.preview())
}
#endif
