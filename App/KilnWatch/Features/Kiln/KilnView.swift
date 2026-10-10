import KilnWatchCore
import MapKit
import SwiftUI

/// Everything about one kiln: evidence, flagged rules, exposure, what to check on site.
struct KilnView: View {
    let id: String
    @Environment(AppModel.self) private var model
    var body: some View {
        Group {
            if model.usesPublicRegistry {
                if case .loaded = model.detailStates[id], let kiln = model.kiln(id) {
                    KilnDetailView(id: id, kiln: kiln)
                } else {
                    ScrollView {
                        RegistryStateView(state: model.detailStates[id] ?? .loading, district: model.district,
                                          retrying: model.isRefreshingDetail(id)) {
                            await model.loadDetail(id, force: true)
                        }
                    }
                    .background(.canvas)
                }
            } else if let kiln = model.kiln(id) { KilnDetailView(id: id, kiln: kiln) }
            else { ContentUnavailableView("Kiln unavailable", systemImage: "questionmark.folder", description: Text("No record is available for \(id).")) }
        }
        .task(id: id) { await model.loadDetail(id) }
        .toolbar { ToolbarItem(placement: .topBarTrailing) { DataSourceLabel(text: model.dataSourceLabel) } }
    }
}

private struct KilnDetailView: View {
    let id: String

    @Environment(AppModel.self) private var model
    @State private var showVerdict = false
    @State private var scroll = ScrollPosition(edge: .top)
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let kiln: Kiln

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.xl) {
                header
                BeforeAfterComparator(kiln: kiln, illustrative: model.usesIllustrativeEvidence(for: kiln), testImages: model.isPublicDemo)
                    .card()
                section("Flagged rules", id: "rules") {
                    VStack(alignment: .leading, spacing: Space.l) {
                        if kiln.rulesAssessment == "not_evaluated" || (kiln.rulesAssessment == nil && kiln.violations.isEmpty) {
                            Text("Rules not evaluated").font(.body).foregroundStyle(.inkSecondary)
                        } else if kiln.violations.isEmpty {
                            Text("No rule flags measured").font(.body).foregroundStyle(.inkSecondary)
                        }
                        ForEach(kiln.violations, id: \.ruleId) { violation in
                            RuleDistanceBar(violation: violation, kiln: kiln, color: model.status(for: kiln).color)
                        }
                        if kiln.rulesAssessment == "partially_evaluated" {
                            Text("Some rules could not be checked from map data. Check on site.")
                                .font(.footnote).foregroundStyle(.inkSecondary)
                        }
                    }
                    .card()
                }
                section(isFixture ? "Within 800 m" : "Population exposure", id: "exposure") {
                    ExposureBlock(exposure: kiln.exposure, bufferRadiusM: isFixture ? 800 : nil).card()
                }
                section(isFixture ? "Nearest home and school" : "Location and footprint", id: "map") {
                    BufferMap(kiln: kiln, illustrative: isFixture).card()
                }
                if isFixture {
                section("Check on site", id: "checks") {
                    SiteChecklist(kiln: kiln, sheet: model.stops.first { $0.kilnId == id }?.sheet).card()
                }
                } else {
                    Text("Sign-in coming soon. Inspection actions aren't available yet.")
                        .font(.footnote)
                        .foregroundStyle(.inkSecondary)
                        .id("checks")
                }
                Button {
                    model.askAboutKiln(kiln.kilnId)
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
        .scrollEdgeEffectStyle(.hard, for: .top)
        .scrollPosition($scroll)
        .background(.canvas)
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaBar(edge: .bottom) { if isFixture { actions } }
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
            if reduceMotion { scroll.scrollTo(id: target, anchor: .top) }
            else { withAnimation(Motion.layout.animation(reduceMotion: false)) { scroll.scrollTo(id: target, anchor: .top) } }
        }
        if isFixture, defaults.bool(forKey: "verdict") {
            try? await Task.sleep(for: .seconds(1))
            showVerdict = true
        }
    }
    #endif

    private var isFixture: Bool { model.usesIllustrativeEvidence(for: kiln) }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text(KilnIDLabel.shortID(kiln.kilnId))
                .font(.largeTitle.weight(.semibold).monospaced())
                .foregroundStyle(.ink)
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel(kiln.kilnId)
            Text(kiln.kilnId)
                // IDs are nonlinguistic: wrap without dictionary-inserted hyphens.
                .typesettingLanguage(.explicit(.init(identifier: "zxx")))
                .font(.footnote.monospaced())
                .foregroundStyle(.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            Text(typeLine)
                .font(.subheadline)
                .foregroundStyle(.inkSecondary)
            StatusBadge(status: model.status(for: kiln), detailed: true)
                .padding(.top, Space.xxs)
            if !isFixture {
                Text("Model score \(kiln.typeConfidence.formatted(.number.precision(.fractionLength(2))))")
                    .font(.subheadline.monospacedDigit()).foregroundStyle(.ink)
                Text("How strongly the model matched this shape; not a rule check")
                    .font(.footnote).foregroundStyle(.inkSecondary)
                VStack(alignment: .leading, spacing: Space.s) {
                    dateLine("First seen on satellite imagery", date: kiln.firstSeen)
                    dateLine("Latest satellite image", date: kiln.lastSeen)
                }
                .padding(.top, Space.s)
            }
        }
        .padding(.top, Space.xs)
    }

    private func dateLine(_ label: String, date: Date) -> some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            Text(label).font(.footnote).foregroundStyle(.inkSecondary)
            Text(date, format: .dateTime.day().month(.wide).year()).font(.subheadline).foregroundStyle(.ink)
        }
        .accessibilityElement(children: .combine)
    }

    private var typeLine: String {
        if !isFixture { return "Predicted \(kiln.type.rawValue) · unverified" }
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
    var illustrative = false

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
            Map(initialPosition: .region(region),
                interactionModes: []) {
                if illustrative {
                MapCircle(center: kiln.coordinate, radius: 800)
                    .foregroundStyle(Color.ink.opacity(0.04))
                    .stroke(Color.ink.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [6, 4]))
                } else if kiln.footprint.polygon.allSatisfy(\.isValid), kiln.footprint.polygon.count >= 3 {
                    MapPolygon(coordinates: kiln.footprint.polygon.map(\.clLocation))
                        .foregroundStyle(Color.clay.opacity(0.12))
                        .stroke(Color.clay, lineWidth: 2)
                }
                Annotation(kiln.kilnId, coordinate: kiln.coordinate) {
                    if illustrative {
                    Rectangle()
                        .stroke(.black.opacity(0.7), lineWidth: 4)
                        .overlay { Rectangle().stroke(.obb, lineWidth: 2) }
                        .frame(width: 22, height: 10)
                        .rotationEffect(.degrees(-28))
                    } else {
                        Circle()
                            .fill(.clay)
                            .frame(width: 8, height: 8)
                    }
                }
                .annotationTitles(.hidden)
                ForEach(illustrative ? points : [], id: \.violation.ruleId) { point in
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

            Text(illustrative ? "Dashed ring: 800 m buffer from the kiln footprint" : "Satellite-detected footprint and location · pending inspection")
                .font(.caption)
                .foregroundStyle(.inkSecondary)
        }
    }

    private var region: MKCoordinateRegion {
        let fallback = MKCoordinateRegion(center: kiln.coordinate, latitudinalMeters: illustrative ? 2_400 : 300, longitudinalMeters: illustrative ? 2_400 : 300)
        let polygon = kiln.footprint.polygon
        guard !illustrative, polygon.count >= 3, polygon.allSatisfy(\.isValid),
              let minLat = polygon.map(\.latitude).min(), let maxLat = polygon.map(\.latitude).max(),
              let minLon = polygon.map(\.longitude).min(), let maxLon = polygon.map(\.longitude).max() else { return fallback }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
        let minimum = MKCoordinateRegion(center: center, latitudinalMeters: 300, longitudinalMeters: 300).span
        return MKCoordinateRegion(center: center, span: MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.4, minimum.latitudeDelta),
            longitudeDelta: max((maxLon - minLon) * 1.4, minimum.longitudeDelta)))
    }

    private var accessibilityText: String {
        if !illustrative { return "Map of \(kiln.kilnId), satellite-detected footprint and location, pending inspection. No siting buffer has been assessed." }
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
                ?? "Distance not measured. Identify the nearest home on site.",
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
    NavigationStack { KilnView(id: "KW-0412") }.environment(AppModel(useFixtures: true))
}
