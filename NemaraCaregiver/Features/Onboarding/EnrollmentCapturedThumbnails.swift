import SwiftUI

/// Horizontal scroll of captured selfies with per-thumbnail delete.
/// Renders below the camera preview during enrollment so the
/// caregiver sees their progress and can re-capture an angle they
/// got wrong without resubmitting.
///
/// Thumbnails are stored as JPEG Data in the parent view's @State,
/// not in any cache — the entire captured set is held in memory
/// during the enrollment session (~12 photos × ~250 KB = ~3 MB,
/// acceptable). After submit, the bytes are POSTed to the backend
/// and the array is cleared.
struct EnrollmentCapturedThumbnails: View {
    @Binding var photos: [Data]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Array(photos.enumerated()), id: \.offset) { idx, data in
                    thumbnail(data: data, atIndex: idx)
                }
            }
            .padding(.horizontal, 16)
        }
        .frame(height: 80)
    }

    @ViewBuilder
    private func thumbnail(data: Data, atIndex idx: Int) -> some View {
        ZStack(alignment: .topTrailing) {
            if let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(
                        RoundedRectangle(cornerRadius: NemaraRadius.sm, style: .continuous),
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: NemaraRadius.sm, style: .continuous)
                            .strokeBorder(NemaraColor.line, lineWidth: 1),
                    )
            }
            Button {
                photos.remove(at: idx)
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(NemaraColor.ink, NemaraColor.paper)
                    .font(.system(size: 16, weight: .bold))
                    .padding(2)
            }
            .buttonStyle(.plain)
        }
    }
}
