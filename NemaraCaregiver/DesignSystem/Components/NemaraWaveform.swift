import SwiftUI

/// Generic audio-level waveform — a horizontal row of vertical bars
/// whose heights track the most-recent N samples of a `[Float]` level
/// stream (range 0.0–1.0).
///
/// **Decoupled from any specific audio source.** Callers pass in an
/// already-computed levels array; producers like
/// `LiveKitClient.audioLevels` keep that array fresh. This keeps the
/// component reusable for future surfaces (mic-test screens, dictation
/// affordances, etc.) without dragging a LiveKit dep into the design
/// system.
///
/// The bars render right-aligned (newest sample on the right) so the
/// shape "slides leftward" as new samples arrive — the standard
/// scrolling-mic-waveform feel.
struct NemaraWaveform: View {
    /// Recent audio peak levels (0.0–1.0). The visual takes the
    /// trailing `barCount` entries.
    let levels: [Float]

    /// How many bars to render. Defaults to a comfortable spoken-
    /// language width for ~3-4s of audio at 20-50 fps.
    var barCount: Int = 40

    /// Bar fill tint. Defaults to the brand accent so the waveform
    /// reads "live"; pass a muted color for idle/inactive states.
    var tint: Color = NemaraColor.terraInk

    /// Minimum bar height so an idle/silent input still shows a faint
    /// baseline, not flat zero. Expressed as a fraction of the
    /// container height (0.05 = 5%).
    var minHeightFraction: CGFloat = 0.06

    var body: some View {
        GeometryReader { geo in
            let displayed = trailing(levels, count: barCount)
            let spacing: CGFloat = 2
            let barWidth = max(
                1,
                (geo.size.width - CGFloat(barCount - 1) * spacing) / CGFloat(barCount),
            )
            HStack(alignment: .center, spacing: spacing) {
                ForEach(0..<barCount, id: \.self) { idx in
                    Capsule()
                        .fill(tint)
                        .frame(
                            width: barWidth,
                            height: barHeight(
                                forIndex: idx,
                                samples: displayed,
                                containerHeight: geo.size.height,
                            ),
                        )
                        .animation(.easeOut(duration: 0.08), value: displayed.count)
                }
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .center)
        }
    }

    /// Index `0` is the oldest visible bar; index `barCount-1` is the
    /// newest. Missing samples (early-frame) render at the floor.
    private func barHeight(
        forIndex idx: Int,
        samples: [Float],
        containerHeight: CGFloat,
    ) -> CGFloat {
        // Right-align: idx -> sample at (len - barCount + idx). When
        // we don't have enough samples yet (rolling buffer warming up),
        // missing slots resolve to the floor height.
        let offset = samples.count - barCount + idx
        let level: Float
        if offset < 0 || offset >= samples.count {
            level = 0
        } else {
            level = samples[offset]
        }
        let floor = containerHeight * minHeightFraction
        let scaled = CGFloat(min(max(level, 0), 1)) * containerHeight
        return max(floor, scaled)
    }

    private func trailing(_ samples: [Float], count: Int) -> [Float] {
        if samples.count <= count { return samples }
        return Array(samples.suffix(count))
    }
}

#Preview {
    VStack(spacing: 24) {
        NemaraWaveform(levels: (0..<40).map { i in
            // Synthetic speech-like shape for the preview.
            let phase = Float(i) / 5
            return abs(sin(phase)) * 0.6 + 0.1
        })
        .frame(height: 36)
        .padding()
        .background(NemaraColor.ink)

        NemaraWaveform(levels: Array(repeating: 0.02, count: 40), tint: NemaraColor.ink3)
            .frame(height: 36)
            .padding()
            .background(NemaraColor.paperDim)
    }
}
