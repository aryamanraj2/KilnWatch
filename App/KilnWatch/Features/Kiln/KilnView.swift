import KilnWatchCore
import MapKit
import SwiftUI

/// Everything about one kiln: evidence, flagged rules, exposure, what to check on site.
struct KilnView: View {
    let id: String
    @Environment(AppModel.self) private var model
    var body: some View {
        if let kiln = model.kiln(id) { KilnDetailView(id: id, kiln: kiln) }
        else { ContentUnavailableView("Kiln unavailable", systemImage: "questionmark.folder", description: Text("No record is available for \(id).")) }
    }
}

private struct KilnDetailView: View {
    let id: String

    @Environment(AppModel.self) private var model
    @State private var showVerdict = false
    @State private var scroll = ScrollPosition(edge: .top)

    let kiln: Kiln

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                header
                BeforeAfterComparator(kiln: kiln)
                    .card()
                section("Flagged rules", id: "rules") {
                    VStack(alignment: .leading, spacing: Space.l) {
                        ForEach(kiln.violations, id: \.ruleId) { violation in
                            RuleDistanceBar(violation: violation, kiln: kiln, color: model.status(for: kiln).color)
                        }
                    }
                    .card()
                }
                section("Within 800 m", id: "exposure") {
                    ExposureBlock(exposure: kiln.exposure).card()
                }
                section("Nearest home and school", id: "map") {
                    BufferMap(kiln: kiln).card()
                }
                section("Check on site", id: "checks") {
                    SiteChecklist(kiln: kiln, sheet: model.stops.first { $0.kilnId == id }?.sheet).card()
                }
                Button {
                    model.askDraft = "Explain the flags on \(kiln.kilnId)."
                    model.tab = .ask
                } label: {
                    HStack {
                        Label("Ask about this kiln", systemImage: "text.bubble")
                            .font(.body.weight(.medium))
                            .foregroundStyle(.ink)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(.inkSecondary)
                            .accessibilityHidden(true)
                    }
                    .frame(minHeight: 44)
                    .card()
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, Space.margin)
            .padding(.bottom, Space.xl)
            .redacted(reason: model.isLoading ? .placeholder : [])
        }
        .scrollPosition($scroll)
        .background(.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaBar(edge: .bottom) { actions }
        .sheet(isPresented: $showVerdict) { VerdictSheet(kilnId: id) }
        #if DEBUG
        .task { await debugAutoplay() }
        #endif
    }

    #if DEBUG
    /// Launch arguments for screenshots and recordings: `-scroll rules`, `-verdict YES`.
    private func debugAutoplay() async {
        let defaults = UserDefaults.standard
        if let target = defaults.string(forKey: "scroll") {
            try? await Task.sleep(for: .seconds(1.5))
            withAnimation(.smooth(duration: 0.6)) { scroll.scrollTo(id: target, anchor: .top) }
        }
        if defaults.bool(forKey: "verdict") {
            try? await Task.sleep(for: .seconds(1))
            showVerdict = true
        }
    }
    #endif

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(kiln.kilnId)
                .font(.largeTitle.weight(.semibold).monospaced())
                .foregroundStyle(.ink)
                .accessibilityAddTraits(.isHeader)
            Text(typeLine)
                .font(.subheadline)
                .foregroundStyle(.inkSecondary)
            StatusBadge(status: model.status(for: kiln), detailed: true)
                .padding(.top, Space.xxs)
        }
        .padding(.top, Space.xs)
    }

    private var typeLine: String {
        let type = kiln.typeIsCertain ? kiln.type.rawValue : "likely \(kiln.type.rawValue)"
        let check = kiln.typeIsCertain ? "" : " · confirm on site"
        return "\(type) · \(kiln.type.longName) · \(kiln.district ?? "District unavailable")\(check)"
    }

    private var actions: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: Space.s) { actionButtons }
            VStack(spacing: Space.xs) { actionButtons }
        }
        .padding(.horizontal, Space.margin)
        .padding(.vertical, Space.xs)
    }

    @ViewBuilder private var actionButtons: some View {
        Button("Directions", systemImage: "arrow.triangle.turn.up.right.diamond") { openDirections() }
            .buttonStyle(.secondary)
        Button("Record verdict") { showVerdict = true }
            .buttonStyle(.primary)
            .disabled(model.isLoading)
    }

    private func section<Content: View>(_ title: String, id: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(title).eyebrow()
            content()
        }
        .id(id)
    }

    private func openDirections() { model.maps.navigate(id: id, model: model) }
}

/// The kiln, its 800 m buffer and the nearest home and school with measured distances.
private struct BufferMap: View {
    let kiln: Kiln

    private var points: [(symbol: String, label: String, violation: Violation)] {
        kiln.violations.compactMap { v in
            guard v.measuredTo != nil, let m = v.measuredDistanceM else { return nil }
            switch v.ruleId {
            case "C-HAB-800": return ("house.fill", "Home · \(Int(m).grouped) m", v)
            case "UP-SCH-1K": return ("graduationcap.fill", "School · \(Int(m).grouped) m", v)
            default: return nil
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Map(initialPosition: .region(MKCoordinateRegion(center: kiln.coordinate, latitudinalMeters: 2_400, longitudinalMeters: 2_400)),
                interactionModes: []) {
                MapCircle(center: kiln.coordinate, radius: 800)
                    .foregroundStyle(Color.ink.opacity(0.04))
                    .stroke(Color.ink.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                Annotation(kiln.kilnId, coordinate: kiln.coordinate) {
                    Rectangle()
                        .stroke(.black.opacity(0.7), lineWidth: 4)
                        .overlay { Rectangle().stroke(.obb, lineWidth: 2) }
                        .frame(width: 22, height: 10)
                        .rotationEffect(.degrees(-28))
                }
                .annotationTitles(.hidden)
                ForEach(points, id: \.violation.ruleId) { point in
                    if let to = point.violation.measuredTo {
                        MapPolyline(coordinates: [kiln.coordinate, to.clLocation])
                            .stroke(Color.ink.opacity(0.5), style: StrokeStyle(lineWidth: 1, dash: [2, 3]))
                        Annotation(point.label, coordinate: to.clLocation, anchor: .leading) {
                            HStack(spacing: Space.xxs) {
                                Image(systemName: point.symbol)
                                    .font(.caption)
                                    .foregroundStyle(.canvas)
                                    .frame(width: 24, height: 24)
                                    .background(.ink, in: .circle)
                                Text(point.label)
                                    .font(.caption.weight(.semibold).monospaced())
                                    .foregroundStyle(.ink)
                                    .padding(.horizontal, Space.xs)
                                    .padding(.vertical, 2)
                                    .background(.surface, in: .capsule)
                                    .fixedSize()
                            }
                        }
                        .annotationTitles(.hidden)
                    }
                }
            }
            .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .frame(height: 220)
            .clipShape(.inner)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)

            Text("Dashed ring: 800 m buffer from the kiln footprint")
                .font(.caption)
                .foregroundStyle(.inkSecondary)
        }
    }

    private var accessibilityText: String {
        let parts = points.map { $0.label.replacingOccurrences(of: " m", with: " metres") }
        return "Map of \(kiln.kilnId) and its 800 metre buffer. " + parts.joined(separator: ". ")
    }
}

/// What the inspector verifies on the ground (concept p.10).
private struct SiteChecklist: View {
    let kiln: Kiln
    var sheet: InspectionSheet?

    private var items: [(title: String, detail: String, symbol: String)] {
        if let sheet {
            return sheet.onSiteChecks.map { (title: $0, detail: "Confirm on site.", symbol: "checklist") }
        }
        let home = kiln.violations.first { $0.ruleId == "C-HAB-800" }
        return [
            ("Chimney type",
             kiln.typeIsCertain ? "Satellite reads \(kiln.type.rawValue). Zigzag is required within 10 km of Delhi."
                                : "Satellite reads likely \(kiln.type.rawValue), confidence \(kiln.typeConfidence.formatted(.number.precision(.fractionLength(2)))). Confirm the design.",
             "building.columns"),
            ("Fuel on site", "Note coal, biomass or other fuel stocked at the kiln.", "shippingbox"),
            ("Distance to the nearest home",
             home.map { "Measured \(Int($0.measuredDistanceM ?? 0).grouped) m. Rule requires \(Int($0.thresholdM ?? 0).grouped) m." }
                ?? "Confirm no homes within 800 m.",
             "ruler"),
        ]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            ForEach(items, id: \.title) { item in
                HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                    Image(systemName: item.symbol)
                        .foregroundStyle(.inkSecondary)
                        .frame(width: 24)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title).font(.body.weight(.semibold)).foregroundStyle(.ink)
                        Text(item.detail).font(.subheadline).foregroundStyle(.inkSecondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }
        }
    }
}

#Preview {
    NavigationStack { KilnView(id: "KW-0412") }.environment(AppModel())
}
