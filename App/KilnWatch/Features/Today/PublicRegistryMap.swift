import KilnWatchCore
import MapKit
import SwiftUI

/// Public candidates have footprints and locations. Planning a route is an explicit, cost-bearing tap.
struct PublicRegistryMap: View {
    let zoom: Namespace.ID
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var camera: MapCameraPosition = .automatic

    private var mappedKilns: [Kiln] { model.allKilns.filter { $0.footprint.centroid.isValid } }
    private var loaded: Bool { if case .loaded = model.registryState { return true }; return false }

    var body: some View {
        Group {
            if loaded {
                Map(position: $camera) {
                    ForEach(mappedKilns) { kiln in
                        if kiln.footprint.polygon.count >= 3, kiln.footprint.polygon.allSatisfy(\.isValid) {
                            MapPolygon(coordinates: kiln.footprint.polygon.map(\.clLocation))
                                .foregroundStyle(Color.flagged.opacity(0.12))
                                .stroke(Color.flagged, lineWidth: 2)
                        }
                        Annotation(kiln.kilnId, coordinate: kiln.coordinate) {
                            Button { model.open(kiln: kiln.kilnId) } label: {
                                Image(systemName: "flag.fill")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.flagged)
                                    .frame(width: 22, height: 22)
                                    .background(.surface, in: .circle)
                                    .frame(minWidth: 44, minHeight: 44)
                                    .contentShape(.rect)
                            }
                            .buttonStyle(.plain)
                            .matchedTransitionSource(id: kiln.kilnId, in: zoom)
                            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                            .accessibilityLabel("\(kiln.kilnId). Flagged by satellite · pending inspection")
                            .accessibilityHint("Opens the satellite record")
                            .accessibilityIdentifier("kiln-pin-\(kiln.kilnId)")
                        }
                        .annotationTitles(.hidden)
                    }
                }
                .mapStyle(.standard(emphasis: .muted, pointsOfInterest: .excludingAll))
                .mapControls { MapScaleView() }
                .safeAreaInset(edge: .top) { header }
                .safeAreaInset(edge: .bottom) { planPanel }
                .onChange(of: model.allKilns, initial: true) { _, records in fit(records) }
                .accessibilityIdentifier("public-kiln-map")
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: Space.s) {
                        Text("Today · \(model.district)").font(.title.weight(.semibold)).foregroundStyle(.ink)
                        DataSourceLabel(text: model.dataSourceLabel)
                        RegistryStateView(state: model.registryState, district: model.district,
                                          retrying: model.registryRefreshing) { await model.loadRegistry(force: true) }
                    }
                    .padding(Space.margin)
                }
                .background(.canvas)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .firstTextBaseline) {
                Text("Today · \(model.district)").font(.headline).foregroundStyle(.ink)
                Spacer(minLength: Space.xs)
                Button("Show all kilns", systemImage: "list.bullet") { model.tab = .kilns }
                    .labelStyle(.iconOnly)
                    .frame(minWidth: 44, minHeight: 44)
                    .buttonStyle(.plain)
                    .accessibilityHint("Opens the searchable registry")
            }
            Text("\(model.allKilns.count) satellite-flagged candidates")
                .font(.subheadline.monospacedDigit()).foregroundStyle(.inkSecondary)
            DataSourceLabel(text: model.dataSourceLabel)
        }
        .padding(Space.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(.regular, in: .rect(cornerRadius: Radius.card, style: .continuous))
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
        .padding(.horizontal, Space.margin)
    }

    private var planPanel: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.s) {
                StatusBadge(status: .flagged, detailed: true)
                Text("Showing satellite-flagged kilns in \(model.district). Tap a pin to view its record.")
                    .font(.subheadline).foregroundStyle(.inkSecondary)
                if let message = model.planner?.failureMessage {
                    Label(message, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(.ink)
                } else if case .failure(let message) = model.routeState {
                    Label(message, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(.ink)
                }
                if let route = model.route {
                    Button("Show saved plan") { model.showAllKilns = false }.buttonStyle(.primary)
                    Text("\(route.dayLabel()) · \(model.routeSummary)").font(.footnote.monospacedDigit()).foregroundStyle(.inkSecondary)
                } else if let planner = model.planner {
                    Button { model.planRoute() } label: {
                        if planner.isPlanning {
                            HStack(spacing: Space.xs) { ProgressView().tint(.canvas); Text("Planning route") }
                        } else { Text(planner.failure?.canRetry == true ? "Try again" : "Plan tomorrow in \(model.district)") }
                    }
                    .buttonStyle(.primary)
                    .disabled(!planner.canPlan())
                    .accessibilityHint("Sends one plan request. It counts toward a shared daily limit.")
                    Text("Up to 8 stops · most people within 800 m · visited in road order")
                        .font(.footnote).foregroundStyle(.inkSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollBounceBehavior(.basedOnSize)
        .fixedSize(horizontal: false, vertical: !typeSize.isAccessibilitySize)
        .frame(maxHeight: typeSize.isAccessibilitySize ? 320 : nil)
        .card(floating: true)
        .padding(.horizontal, Space.margin)
        .padding(.bottom, Space.xs)
    }

    private func fit(_ records: [Kiln]) {
        let points = records.flatMap { [$0.footprint.centroid] + $0.footprint.polygon }.filter(\.isValid)
        guard let minLat = points.map(\.latitude).min(), let maxLat = points.map(\.latitude).max(),
              let minLon = points.map(\.longitude).min(), let maxLon = points.map(\.longitude).max() else { return }
        let region = MKCoordinateRegion(center: .init(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
                                        span: .init(latitudeDelta: max((maxLat - minLat) * 1.4, 0.01),
                                                    longitudeDelta: max((maxLon - minLon) * 1.4, 0.01)))
        if reduceMotion { camera = .region(region) }
        else { withAnimation(Motion.layout.animation(reduceMotion: false)) { camera = .region(region) } }
    }
}
