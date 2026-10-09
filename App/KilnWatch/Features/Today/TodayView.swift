import MapKit
import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Namespace private var zoom

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.todayPath) {
            RouteMap(zoom: zoom)
                .toolbarVisibility(.hidden, for: .navigationBar)
                .navigationDestination(for: String.self) { id in
                    KilnView(id: id)
                        .navigationTransition(.zoom(sourceID: id, in: zoom))
                }
        }
    }
}

private struct RouteMap: View {
    let zoom: Namespace.ID

    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var camera: MapCameraPosition = .camera(MapCamera(centerCoordinate: Self.overviewCenter, distance: 52_000))
    @State private var focused: String? = Mock.stops.first?.kilnID
    @State private var imagery = UserDefaults.standard.bool(forKey: "imagery")
    @State private var showList = UserDefaults.standard.bool(forKey: "routeList")

    /// Fixed camera distance, so large text sizes don't zoom the route out to the whole state.
    private static let overviewCenter = CLLocationCoordinate2D(latitude: 28.735, longitude: 77.74)

    var body: some View {
        let showsRoute = model.hasRoute && !model.isLoading
        Map(position: $camera) {
            if showsRoute {
                MapPolyline(coordinates: model.stops.map { model.kiln($0.kilnID).coordinate })
                    .stroke(.clay, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                ForEach(model.stops) { stop in
                    Annotation(stop.kilnID, coordinate: model.kiln(stop.kilnID).coordinate) {
                        StopPin(stop: stop, isSelected: focused == stop.kilnID) { focus(stop.kilnID) }
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    }
                    .annotationTitles(.hidden)
                }
            }
        }
        .mapStyle(imagery ? .imagery(elevation: .flat) : .standard(emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControls { MapScaleView() }
        .overlay(alignment: .top) {
            // Scrim over imagery only, so the header never depends on glass translucency.
            LinearGradient(colors: [.black.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 160)
                .ignoresSafeArea()
                .opacity(imagery ? 1 : 0)
                .allowsHitTesting(false)
        }
        .safeAreaInset(edge: .top) { header }
        .safeAreaInset(edge: .bottom) {
            if model.hasRoute { carousel } else { emptyState }
        }
        .onChange(of: focused) { _, id in fly(to: id) }
        .sensoryFeedback(.impact(weight: .light), trigger: focused) { _, new in new != nil }
        #if DEBUG
        .task {
            // `-autoplay carousel`: walk the carousel for the recording.
            guard UserDefaults.standard.string(forKey: "autoplay") == "carousel" else { return }
            for stop in model.stops.prefix(5).dropFirst() {
                try? await Task.sleep(for: .seconds(2))
                focus(stop.kilnID)
            }
        }
        #endif
        .sheet(isPresented: $showList) {
            RouteListSheet { id in
                showList = false
                focus(id)
            }
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            GlassEffectContainer(spacing: Space.xs) {
                HStack(alignment: .top, spacing: Space.xs) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Today · Hapur")
                            .font(.headline)
                        Text(model.hasRoute ? "9 stops · 5\u{00A0}h 40\u{00A0}m · leave 9:00" : "No route")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .redacted(reason: model.isLoading ? .placeholder : [])
                    }
                    .padding(.horizontal, Space.m)
                    .padding(.vertical, Space.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular, in: .rect(cornerRadius: Radius.card, style: .continuous))
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)

                    VStack(spacing: Space.xs) {
                        Button("Route list", systemImage: "list.number") { showList = true }
                            .disabled(!model.hasRoute)
                        Button(imagery ? "Standard map" : "Satellite imagery",
                               systemImage: imagery ? "map" : "globe.asia.australia") {
                            imagery.toggle()
                        }
                        .sensoryFeedback(.selection, trigger: imagery)
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .controlSize(.large)
                }
            }
            HStack(spacing: Space.xs) {
                if model.isOffline {
                    QuietBanner(text: "Offline · showing saved route", systemImage: "wifi.slash")
                }
                #if DEBUG
                QuietBanner(text: "Sample data", systemImage: nil)
                #endif
            }
        }
        .padding(.horizontal, Space.margin)
    }

    // MARK: Carousel

    private var carousel: some View {
        VStack(spacing: Space.s) {
            ScrollView(.horizontal) {
                LazyHStack(spacing: Space.s) {
                    ForEach(model.stops) { stop in
                        NavigationLink(value: stop.kilnID) {
                            StopCard(stop: stop, kiln: model.kiln(stop.kilnID))
                        }
                        .buttonStyle(.plain)
                        .matchedTransitionSource(id: stop.kilnID, in: zoom)
                        .containerRelativeFrame(.horizontal) { width, _ in width - Space.margin * 3 }
                        .id(stop.kilnID)
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(id: $focused, anchor: .leading)
            .scrollIndicators(.hidden)
            .contentMargins(.horizontal, Space.margin, for: .scrollContent)
            .scrollClipDisabled()
            .fixedSize(horizontal: false, vertical: true)
            .redacted(reason: model.isLoading ? .placeholder : [])
            .disabled(model.isLoading)

            Button(model.routeActive ? "End route" : "Start route") {
                withAnimation(Motion.layout.animation(reduceMotion: reduceMotion)) {
                    model.routeActive.toggle()
                    model.currentStop = 0
                }
            }
            .buttonStyle(model.routeActive ? .secondary : .primary)
            .padding(.horizontal, Space.margin)
            .disabled(model.isLoading)
        }
        .padding(.bottom, Space.xs)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No route planned for today", systemImage: "map")
        } description: {
            Text("Ask the planner to build one from the flagged kilns in Hapur.")
        } actions: {
            Button("Plan a route") { model.planRouteInAsk() }
                .buttonStyle(.primary)
        }
        .foregroundStyle(.ink)
        .card(floating: true)
        .padding(.horizontal, Space.margin)
        .padding(.bottom, Space.xs)
    }

    // MARK: Camera

    private func focus(_ id: String) {
        withAnimation(Motion.select.animation(reduceMotion: reduceMotion)) { focused = id }
    }

    private func fly(to id: String?) {
        guard let id else { return }
        let target = MapCameraPosition.camera(MapCamera(centerCoordinate: model.kiln(id).coordinate, distance: 9_000))
        if reduceMotion {
            camera = target
        } else {
            withAnimation(Motion.layout.animation(reduceMotion: false)) { camera = target }
        }
    }
}

/// One stop: number, kiln, its most severe rule as one line, people exposed.
private struct StopCard: View {
    let stop: Stop
    let kiln: Kiln
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                Text(stop.number, format: .number)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(.inkSecondary)
                KilnIDLabel(kiln: kiln)
            }
            if let top = kiln.topViolation {
                Text(top.factLine(for: kiln))
                    .font(.subheadline)
                    .foregroundStyle(.ink)
                    .lineLimit(typeSize.isAccessibilitySize ? nil : 2)
            }
            Text("\(Text(kiln.exposure.peopleWithin800m.grouped).fontWeight(.semibold)) people within 800 m")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.inkSecondary)
        }
        .card(floating: true)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens the kiln")
    }
}

/// Quiet, solid status line under the header.
struct QuietBanner: View {
    let text: String
    let systemImage: String?

    var body: some View {
        HStack(spacing: Space.xxs) {
            if let systemImage { Image(systemName: systemImage).accessibilityHidden(true) }
            Text(text)
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(.inkSecondary)
        .padding(.horizontal, Space.s)
        .padding(.vertical, Space.xxs)
        .background(.surface, in: .capsule)
    }
}

/// The full ordered route.
private struct RouteListSheet: View {
    let select: (String) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(model.stops) { stop in
                let kiln = model.kiln(stop.kilnID)
                Button { select(stop.kilnID) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                        Text(stop.number, format: .number)
                            .font(.body.weight(.semibold).monospacedDigit())
                            .foregroundStyle(.inkSecondary)
                            .frame(minWidth: 20, alignment: .trailing)
                        VStack(alignment: .leading, spacing: Space.xxs) {
                            KilnIDLabel(kiln: kiln)
                            if let top = kiln.topViolation {
                                Text(top.factLine(for: kiln))
                                    .font(.subheadline)
                                    .foregroundStyle(.ink)
                            }
                            Text("\(kiln.exposure.peopleWithin800m.grouped) people · \(stop.driveMinutes) min drive")
                                .font(.footnote.monospacedDigit())
                                .foregroundStyle(.inkSecondary)
                        }
                    }
                    .padding(.vertical, Space.xxs)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
            }
            .navigationTitle("Route · \(model.stops.count) stops")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark", role: .close) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    TodayView().environment(AppModel())
}
