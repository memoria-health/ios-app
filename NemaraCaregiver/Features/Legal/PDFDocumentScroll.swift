import PDFKit
import SwiftUI

/// A read-only, scrollable view of a bundled PDF that reports when the reader
/// has scrolled past the last page. Used by the terms gate to unlock "I agree"
/// only after the whole document has been seen.
///
/// Pages are rasterised (PDFKit -> UIImage) and shown in a plain SwiftUI
/// ScrollView with a zero-height sentinel below the last page — its `.onAppear`
/// is the scroll-to-bottom signal. This keeps end-detection reliable and avoids
/// reaching into PDFView's private scroll view (which fights Swift 6
/// concurrency). No zoom/selection is needed for a terms document.
struct PDFDocumentScroll: View {
    let resource: String
    let onReachedEnd: () -> Void

    @State private var pages: [UIImage] = []
    @State private var state: LoadState = .loading

    private enum LoadState { case loading, ready, failed }

    var body: some View {
        ScrollView {
            switch state {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 64)
            case .failed:
                Text("Couldn't load this document. Pull down to retry.")
                    .font(NemaraFont.bodySmall)
                    .foregroundStyle(NemaraColor.terra)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 64)
            case .ready:
                LazyVStack(spacing: 10) {
                    ForEach(pages.indices, id: \.self) { i in
                        Image(uiImage: pages[i])
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .overlay(
                                Rectangle().strokeBorder(NemaraColor.line, lineWidth: 1)
                            )
                    }
                    // Sentinel: only enters the viewport once scrolled past the
                    // last page → the scroll-to-bottom signal.
                    Color.clear
                        .frame(height: 1)
                        .onAppear { onReachedEnd() }
                }
                .padding(12)
            }
        }
        .task { await load() }
    }

    private func load() async {
        await Task.yield()  // let the ProgressView paint before the render pass
        let rendered = render()
        pages = rendered
        state = rendered.isEmpty ? .failed : .ready
    }

    /// Rasterise every page at a fixed width (SwiftUI scales it down to fit).
    /// Runs on the main actor — fine for the small terms/privacy docs; a large
    /// production doc could move this to a background Core Graphics pass.
    private func render() -> [UIImage] {
        guard
            let url = Bundle.main.url(forResource: resource, withExtension: "pdf"),
            let doc = PDFDocument(url: url)
        else { return [] }

        let width: CGFloat = 1200
        var images: [UIImage] = []
        for i in 0..<doc.pageCount {
            guard let page = doc.page(at: i) else { continue }
            let b = page.bounds(for: .mediaBox)
            guard b.width > 0, b.height > 0 else { continue }
            let scale = width / b.width
            let size = CGSize(width: width, height: b.height * scale)
            let img = UIGraphicsImageRenderer(size: size).image { ctx in
                UIColor.white.setFill()
                ctx.fill(CGRect(origin: .zero, size: size))
                let cg = ctx.cgContext
                cg.translateBy(x: 0, y: size.height)
                cg.scaleBy(x: scale, y: -scale)
                page.draw(with: .mediaBox, to: cg)
            }
            images.append(img)
        }
        return images
    }
}
