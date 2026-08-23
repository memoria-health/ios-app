import SwiftUI

/// The grab handle at the top of a bottom sheet, and the breathing room
/// underneath it.
///
/// Five sheets each carried their own copy of the same four lines
/// (`Capsule().fill(.line).frame(width: 36, height: 4).padding(.top, 8)`)
/// and then started their content immediately, so every one of them had
/// its first line of text crowding the sheet's edge. Copies drift, and
/// the gap under a handle is a house style rather than a per-sheet
/// decision, so it lives here.
///
/// Hidden from VoiceOver: it is decoration. The sheet is dismissed with
/// the drag gesture or an explicit Close, both of which are announced.
struct NemaraSheetHandle: View {
    /// Distance from the sheet's own top edge to the handle.
    static let topInset: CGFloat = 10
    /// Distance from the handle to the sheet's first line of content.
    /// The value the sheets were all missing.
    static let contentGap: CGFloat = 18

    var body: some View {
        Capsule()
            .fill(NemaraColor.line)
            .frame(width: 36, height: 4)
            .padding(.top, Self.topInset)
            .padding(.bottom, Self.contentGap)
            .accessibilityHidden(true)
    }
}

#if DEBUG
#Preview {
    VStack(spacing: 0) {
        NemaraSheetHandle()
        Text("ADD A SENSOR").nemaraEyebrow()
        Text("Read this to your installer")
            .font(NemaraFont.title3)
        Spacer()
    }
    .frame(maxWidth: .infinity)
    .background(NemaraColor.paper)
}
#endif
