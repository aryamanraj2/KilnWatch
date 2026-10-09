import MapKit
import SwiftUI

/// 2024 against Oct 2026 imagery with a draggable divider and the detector's oriented box.
/// Phase 0 uses one Apple Maps imagery snapshot for both sides, labelled "Illustrative imagery".
struct BeforeAfterComparator: View {
    let kiln: Kiln

    @State private var split: CGFloat = 0.5
    @State private var width: CGFloat = 0
    @State private var image: UIImage?
    @State private var hinted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Color.surface2
                .aspectRatio(1, contentMode: .fit)
                .overlay { imagery }
                .overlay(alignment: .top) { labels }
                .overlay { divider }
                // Labels drawn on imagery stay at map-label scale.
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                .clipShape(.inner)
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Satellite imagery, 2024 and October 2026, with the detected kiln outlined")
                .accessibilityValue("Divider at \(Int(split * 100)) percent")
                .accessibilityAdjustableAction { direction in
                    switch direction {
                    case .increment: split = min(split + 0.1, 1)
                    case .decrement: split = max(split - 0.1, 0)
                    @unknown default: break
                    }
                }
            ViewThatFits(in: .horizontal) {
                HStack { caption }
                VStack(alignment: .leading, spacing: Space.xxs) { caption }
            }
        }
        .task(id: kiln.kilnID) { await loadSnapshot() }
    }

    @ViewBuilder private var caption: some View {
        Text("Sentinel-2 · 10 m · 14 Oct 2026")
            .font(.caption.monospaced())
            .foregroundStyle(.inkSecondary)
        Spacer(minLength: Space.xs)
        Text("Illustrative imagery")
            .font(.caption)
            .foregroundStyle(.inkSecondary)
    }

    @ViewBuilder private var imagery: some View {
        if let image {
            ZStack {
                scene(image)
                scene(image)
                    .mask(alignment: .leading) { Rectangle().frame(width: width * split) }
            }
            .transition(.opacity)
        } else {
            ProgressView()
        }
    }

    private func scene(_ image: UIImage) -> some View {
        Image(uiImage: image)
            .resizable()
            .scaledToFill()
            .overlay { OrientedBox(label: tag) }
            .accessibilityHidden(true)
    }

    private var tag: String {
        "\(kiln.type.rawValue) \(kiln.typeConfidence.formatted(.number.precision(.fractionLength(2))))"
    }

    private var labels: some View {
        HStack {
            ScrimLabel(text: "2024")
            Spacer()
            ScrimLabel(text: "Oct 2026")
        }
        .padding(Space.xs)
        .accessibilityHidden(true)
    }

    private var divider: some View {
        Rectangle()
            .fill(.white)
            .frame(width: 2)
            .overlay(alignment: .bottom) {
                Image(systemName: "chevron.left.chevron.right")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Color.black)
                    .frame(width: 32, height: 32)
                    .background(.white, in: .circle)
                    .shadow(color: .black.opacity(0.2), radius: 2)
                    .padding(.bottom, Space.xxxl)
            }
            .frame(width: 44)
            .contentShape(.rect)
            .position(x: width * split, y: width / 2)
            .gesture(
                DragGesture(minimumDistance: 2)
                    .onChanged { split = min(max($0.location.x / max(width, 1), 0), 1) }
            )
            .opacity(image == nil ? 0 : 1)
            .accessibilityHidden(true)
    }

    private func loadSnapshot() async {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(center: kiln.coordinate, latitudinalMeters: 1300, longitudinalMeters: 1300)
        options.size = CGSize(width: 480, height: 480)
        options.scale = displayScale
        options.preferredConfiguration = MKImageryMapConfiguration()
        guard let snapshot = try? await MKMapSnapshotter(options: options).start() else { return }
        withAnimation(.easeOut(duration: 0.2)) { image = snapshot.image }
        guard !hinted, !reduceMotion, width > 0 else { return }
        hinted = true
        try? await Task.sleep(for: .milliseconds(400))
        withAnimation(.smooth(duration: 0.3)) { split = 0.5 + 12 / width } completion: {
            withAnimation(.smooth(duration: 0.3)) { split = 0.5 }
        }
    }
}

/// Label on a small dark scrim, legible over any imagery.
private struct ScrimLabel: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(.white)
            .padding(.horizontal, Space.xs)
            .padding(.vertical, Space.xxs)
            .background(.black.opacity(0.55), in: .capsule)
    }
}

/// The detector's rotated box: 2 pt OBB yellow with a 1 pt dark outer stroke, plus its type tag.
private struct OrientedBox: View {
    let label: String

    var body: some View {
        GeometryReader { proxy in
            let side = min(proxy.size.width, proxy.size.height)
            ZStack {
                Rectangle().stroke(.black.opacity(0.7), lineWidth: 4)
                Rectangle().stroke(.obb, lineWidth: 2)
            }
            .frame(width: side * 0.17, height: side * 0.07)
            .rotationEffect(.degrees(-28))
            .overlay(alignment: .top) {
                Text(label)
                    .font(.caption2.weight(.semibold).monospaced())
                    .foregroundStyle(Color.black)
                    .padding(.horizontal, Space.xxs)
                    .background(.obb, in: .rect(cornerRadius: 3))
                    .fixedSize()
                    .offset(y: -side * 0.09)
            }
            .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
        }
    }
}

#Preview {
    ScrollView {
        BeforeAfterComparator(kiln: Mock.route[0])
            .padding(Space.margin)
    }
    .background(.canvas)
}
