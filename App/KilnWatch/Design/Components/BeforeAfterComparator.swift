import KilnWatchCore
import MapKit
import SwiftUI

/// 2024 against Oct 2026 imagery with a draggable divider and the detector's oriented box.
/// Phase 0 uses one Apple Maps imagery snapshot for both sides, labelled "Illustrative imagery".
struct BeforeAfterComparator: View {
    let kiln: Kiln
    var illustrative = true
    var testImages = false

    var body: some View {
        if illustrative { IllustrativeComparator(kiln: kiln) }
        else { SatelliteComparator(kiln: kiln, allowsTestImages: testImages) }
    }
}

private struct IllustrativeComparator: View {
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
        .task(id: kiln.kilnId) { await loadSnapshot() }
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

/// Published evidence only: native pixels, per-side metadata, no photo fallback.
private struct SatelliteComparator: View {
    let kiln: Kiln
    var allowsTestImages = false
    @State private var before: UIImage?
    @State private var after: UIImage?
    @State private var loading = true
    @State private var failed = false
    @State private var split: CGFloat = 0.5
    @State private var width: CGFloat = 0
    @State private var retry = 0
    @Environment(\.displayScale) private var displayScale

    private var fixture: String? { allowsTestImages ? DemoOptions.string("evidenceFixture") : nil }
    private var hasPair: Bool { fixture != nil || (kiln.evidence.before != nil && kiln.evidence.after != nil) }
    private var patchPixels: CGFloat { CGFloat(kiln.evidence.afterMetadata?.patchPx ?? 256) }
    /// Integer native-pixel magnification, measured in device pixels rather than points.
    private var side: CGFloat {
        guard width > 0, patchPixels > 0, displayScale > 0 else { return 0 }
        let multiple = floor(width * displayScale / patchPixels)
        return multiple >= 1 ? patchPixels * multiple / displayScale : 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            if !hasPair {
                Label("Satellite images not yet published", systemImage: "photo")
                    .font(.body).foregroundStyle(.inkSecondary)
            } else if failed {
                Label("Satellite images couldn't be loaded", systemImage: "exclamationmark.circle")
                    .font(.body).foregroundStyle(.inkSecondary)
                Button("Retry images", systemImage: "arrow.clockwise") { retry += 1 }
                    .buttonStyle(.secondary)
            } else if loading {
                ProgressView("Loading satellite images")
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else if let before, let after {
                Color.surface2
                    .aspectRatio(1, contentMode: .fit)
                    .overlay {
                        if side > 0 {
                            ZStack(alignment: .topLeading) {
                                scene(after, metadata: kiln.evidence.afterMetadata)
                                scene(before, metadata: kiln.evidence.beforeMetadata)
                                    .mask(alignment: .leading) { Rectangle().frame(width: side * split) }
                                HStack {
                                    ScrimLabel(text: fixture == nil ? shortDate(kiln.evidence.beforeMetadata?.acquiredAt) : "Before · test")
                                    Spacer()
                                    ScrimLabel(text: fixture == nil ? shortDate(kiln.evidence.afterMetadata?.acquiredAt) : "After · test")
                                }
                                .padding(Space.xs)
                                Rectangle().fill(.white).frame(width: 2, height: side)
                                    .overlay(alignment: .bottom) {
                                        Image(systemName: "chevron.left.chevron.right")
                                            .font(.footnote.weight(.bold)).foregroundStyle(.black)
                                            .frame(width: 32, height: 32).background(.white, in: .circle)
                                            .padding(.bottom, Space.xl)
                                    }
                                    .frame(width: 44, height: side)
                                    .contentShape(.rect)
                                    .position(x: side * split, y: side / 2)
                            }
                            .frame(width: side, height: side)
                            .clipShape(.rect)
                            .gesture(DragGesture(minimumDistance: 2).onChanged { split = min(max($0.location.x / side, 0), 1) })
                            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                        } else { Text("More space is needed to display native pixels").font(.caption).foregroundStyle(.inkSecondary) }
                    }
                    .clipShape(.inner)
                    .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(fixture == nil ? "Satellite before and after images. \(dateDescription). Detected footprint shown where metadata is available." : "Synthetic before and after image fixture, for testing only")
                    .accessibilityValue("Divider at \(Int(split * 100)) percent")
                    .accessibilityAdjustableAction { direction in
                        switch direction {
                        case .increment: split = min(split + 0.1, 1)
                        case .decrement: split = max(split - 0.1, 0)
                        @unknown default: break
                        }
                    }
                    .accessibilityIdentifier("satellite-comparator")
            }
            if hasPair {
                if fixture != nil {
                    Text("Synthetic local image fixture · not satellite evidence")
                        .font(.caption).foregroundStyle(.inkSecondary)
                } else {
                    evidenceCaption("Before", metadata: kiln.evidence.beforeMetadata)
                    evidenceCaption("After", metadata: kiln.evidence.afterMetadata)
                }
            }
        }
        .task(id: retry) { await loadImages() }
    }

    private func scene(_ image: UIImage, metadata: EvidenceMetadata?) -> some View {
        Image(uiImage: image)
            .resizable().interpolation(.none)
            .frame(width: side, height: side)
            .overlay {
                if let metadata, let points = metadata.footprintPx, points.count >= 3,
                   points.allSatisfy({ $0.count == 2 && $0.allSatisfy(\.isFinite) }) {
                    let path = Path { path in
                        for (index, point) in points.enumerated() {
                            let p = CGPoint(x: point[0] / Double(metadata.patchPx) * side,
                                            y: point[1] / Double(metadata.patchPx) * side)
                            if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
                        }
                        path.closeSubpath()
                    }
                    path.stroke(.black.opacity(0.7), lineWidth: 4)
                    path.stroke(.obb, lineWidth: 2)
                }
            }
            .accessibilityHidden(true)
    }

    private func evidenceCaption(_ title: String, metadata: EvidenceMetadata?) -> some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            if let metadata {
                Text("\(title) · \(metadata.acquiredAt.formatted(.dateTime.day().month(.abbreviated).year())) · \(metadata.gsdM.formatted()) m pixels")
                    .font(.caption.monospaced()).foregroundStyle(.inkSecondary)
                Text(metadata.attribution).font(.caption).foregroundStyle(.inkSecondary)
            } else {
                Text("\(title) · acquisition date and attribution unavailable")
                    .font(.caption).foregroundStyle(.inkSecondary)
            }
        }
    }

    private func shortDate(_ date: Date?) -> String { date?.formatted(.dateTime.day().month(.abbreviated).year()) ?? "Date unavailable" }
    private var dateDescription: String { "Before \(shortDate(kiln.evidence.beforeMetadata?.acquiredAt)), after \(shortDate(kiln.evidence.afterMetadata?.acquiredAt))" }

    private func loadImages() async {
        guard hasPair else { loading = false; return }
        loading = true; failed = false; before = nil; after = nil
        #if DEBUG
        if fixture == "loading" { return }
        if fixture == "failed" { loading = false; failed = true; return }
        #endif
        let beforeURL: URL?, afterURL: URL?
        #if DEBUG
        if fixture != nil {
            beforeURL = Bundle.main.url(forResource: "EvidenceBefore", withExtension: "png")
            afterURL = Bundle.main.url(forResource: "EvidenceAfter", withExtension: "png")
        } else { beforeURL = kiln.evidence.before; afterURL = kiln.evidence.after }
        #else
        beforeURL = kiln.evidence.before; afterURL = kiln.evidence.after
        #endif
        do {
            guard let beforeURL, let afterURL else { throw EvidenceImageError.unavailable }
            async let beforeData = EvidenceImageData.load(from: beforeURL)
            async let afterData = EvidenceImageData.load(from: afterURL)
            let (b, a) = try await (beforeData, afterData)
            guard let bImage = UIImage(data: b), let aImage = UIImage(data: a),
                  let bCG = bImage.cgImage, let aCG = aImage.cgImage,
                  bCG.width == bCG.height, aCG.width == aCG.height,
                  bCG.width == (kiln.evidence.beforeMetadata?.patchPx ?? 256),
                  aCG.width == (kiln.evidence.afterMetadata?.patchPx ?? 256),
                  bCG.width == aCG.width, (1...2048).contains(aCG.width) else { throw EvidenceImageError.invalidPNG }
            try Task.checkCancellation()
            before = bImage; after = aImage; loading = false
        } catch {
            guard !Task.isCancelled else { return }
            loading = false; failed = true
        }
    }
}
