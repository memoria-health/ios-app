import SwiftUI

/// The explainer behind the ⓘ on `EvaluationModeCard`.
///
/// This sheet is not decoration. Evaluation mode is ON by default, so for
/// most households this page is the first and only place they learn that
/// a person at Memoria sees masked footage of their home. Treat the copy
/// as a disclosure: it has to say plainly who sees what, that sound is
/// included, that a real alert is never delayed, and how to switch it
/// off. If the behaviour changes, this text changes with it.
///
/// The mask image is a real frame from the real pipeline (see
/// `Assets.xcassets/EvaluationModeMask`), staged deliberately rather than
/// taken from a customer's home. Showing an approximation would defeat
/// the point of the page, which is to let someone verify the claim rather
/// than take our word for it.
struct EvaluationModeInfoSheet: View {
    @Environment(\.dismiss) private var dismiss

    /// Assets.xcassets may not carry the frame yet. Render an honest
    /// placeholder rather than a blank gap, so a missing asset is
    /// obvious in review instead of silently shipping an empty box.
    private var maskImage: Image? {
        UIImage(named: "EvaluationModeMask").map(Image.init(uiImage:))
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    // Image FIRST. It is the whole argument: a caregiver
                    // decides whether this is acceptable by looking, not by
                    // reading. Every word below refers back to it.
                    maskSection
                    Text("Evaluation mode")
                        .font(NemaraFont.title2)
                        .foregroundStyle(NemaraColor.ink)
                    body("Video data is not always perfect, and sometimes "
                         + "our AI gets things wrong.")
                    body("Evaluation mode adds a second pair of eyes. Before "
                         + "an alert reaches you, a trained member of our "
                         + "team takes a quick look and stops the false "
                         + "alarms, so you only get notified about the things "
                         + "that matter.")
                    body("The picture above is all they see. Faces, bodies "
                         + "and clothing are covered by a solid shape, so "
                         + "they can tell what happened without seeing who "
                         + "it is. They can hear the clip as well, because a "
                         + "call for help is often the clearest sign that "
                         + "something is wrong.")
                    body("You can turn this off at any time.")
                }
                .padding(24)
            }
            .background(NemaraColor.paper)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private var maskSection: some View {
        Group {
            if let maskImage {
                maskImage
                    .resizable()
                    .scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(NemaraColor.line, lineWidth: 1)
                    )
                    .accessibilityLabel(
                        "A room with the person covered by a solid green shape"
                    )
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(NemaraColor.paperDim)
                    .frame(height: 180)
                    .overlay(
                        Text("Example image not bundled")
                            .font(NemaraFont.caption)
                            .foregroundStyle(NemaraColor.ink4)
                    )
            }
        }
    }

    private func body(_ text: String) -> some View {
        Text(text)
            .font(NemaraFont.body)
            .foregroundStyle(NemaraColor.ink2)
            .fixedSize(horizontal: false, vertical: true)
    }
}
