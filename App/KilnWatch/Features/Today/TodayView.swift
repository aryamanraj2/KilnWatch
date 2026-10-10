import KilnWatchCore
import MapKit
import SwiftUI

struct TodayView: View {
    @Environment(AppModel.self) private var model
    @Namespace private var zoom
    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.todayPath) {
            Group {
                if model.usesPublicRegistry && (model.route == nil || model.showAllKilns) { PublicRegistryMap(zoom: zoom) }
                else { RouteMap(zoom: zoom) }
            }
                .toolbarVisibility(.hidden, for: .navigationBar)
                .navigationDestination(for: String.self) { id in
                    KilnView(id: id).navigationTransition(.zoom(sourceID: id, in: zoom))
                }
        }
    }
}

private struct RouteMap: View {
    let zoom: Namespace.ID
    @Environment(AppModel.self) private var model
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @State private var location = ForegroundLocation()
    @State private var camera: MapCameraPosition = .automatic
    @State private var imagery = DemoOptions.bool("imagery")
    @State private var showList = DemoOptions.bool("routeList")
    @State private var showLocationNotice = false
    @State private var refresh = 0
    @State private var fittedRoute: Route?
    @State private var framingOverview = true
    private var locationActive: Bool { scenePhase == .active && model.tab == .today && model.todayPath.isEmpty && !showList }

    var body: some View {
        @Bindable var model = model
        GeometryReader { layout in
        Map(position: $camera) {
            if let route = model.route {
                ForEach(Array((route.legs ?? []).enumerated()), id: \.offset) { _, leg in
                    if let geometry = leg.geometry, !geometry.validatedCoordinates.isEmpty,
                       model.stops.contains(where: { $0.kilnId == leg.toKilnId }) {
                        MapPolyline(coordinates: geometry.validatedCoordinates.map(\.clLocation))
                            .stroke(.clay, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    }
                }
            }
            ForEach(model.stops) { stop in
                if let kiln = model.kiln(stop.kilnId) {
                    Annotation(stop.kilnId, coordinate: kiln.coordinate) {
                        StopPin(stop: stop, isSelected: model.selectedStopId == stop.kilnId) { focus(stop.kilnId) }
                            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
                    }.annotationTitles(.hidden)
                }
            }
            if location.authorized && locationActive { UserAnnotation() }
        }
        .mapStyle(imagery ? .imagery(elevation: .flat) : .standard(emphasis: .muted, pointsOfInterest: .excludingAll))
        .mapControls { MapScaleView() }
        .overlay(alignment: .top) {
            LinearGradient(colors: [.black.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 160).ignoresSafeArea().opacity(imagery ? 1 : 0).allowsHitTesting(false)
        }
        .onGeometryChange(for: CGRect.self) { proxy in
            CGRect(x: proxy.safeAreaInsets.leading, y: proxy.safeAreaInsets.top,
                   width: max(0, proxy.size.width - proxy.safeAreaInsets.leading - proxy.safeAreaInsets.trailing),
                   height: max(0, proxy.size.height - proxy.safeAreaInsets.top - proxy.safeAreaInsets.bottom))
        } action: { _ in
            // Refit when the actual map viewport changes, including settled insets and text size.
            if framingOverview { moveCamera(model.overview) }
        }
        .safeAreaInset(edge: .top) { header }
        .safeAreaInset(edge: .bottom) {
            if model.hasRoute { carousel(maxHeight: layout.size.height * 0.42) } else { statePanel }
        }
        .onChange(of: model.route, initial: true) { _, route in
            guard let route, fittedRoute != route else { return }
            fittedRoute = route
            framingOverview = true
            moveCamera(model.overview)
            #if DEBUG
            if DemoOptions.string("selected") != nil { fly(to: model.selectedStopId) }
            #endif
        }
        .onChange(of: camera.positionedByUser) { _, byUser in
            if byUser { framingOverview = false }
        }
        .onChange(of: model.selectedStopId) { previous, id in
            // The initial selection is established while fitting the route, not a camera feedback loop.
            if previous != nil, fittedRoute == model.route { fly(to: id) }
        }
        .onChange(of: locationActive, initial: true) { _, active in location.setActive(active) }
        .onChange(of: location.fixSerial) {
            guard let coordinate = location.coordinate else { return }
            framingOverview = false
            moveCamera(.region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 4_000, longitudinalMeters: 4_000)))
        }
        .sensoryFeedback(.impact(weight: .light), trigger: model.selectedStopId) { _, new in new != nil }
        .task(id: refresh) { if refresh > 0 { await model.loadRoute(force: true) } }
        .sheet(isPresented: $showList) {
            RouteListSheet { id in showList = false; focus(id) }
        }
        .alert("Your location", isPresented: $showLocationNotice) {
            if location.settingsAvailable {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
            }
            Button("Close", role: .cancel) { }
        } message: { Text(location.notice ?? "Location is temporarily unavailable. Route browsing remains available.") }
        #if DEBUG
        .task(id: model.hasRoute) {
            guard model.hasRoute, DemoOptions.string("autoplay") == "carousel" else { return }
            for stop in model.stops.prefix(5).dropFirst() {
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                focus(stop.kilnId)
            }
        }
        #endif
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            GlassEffectContainer(spacing: Space.xs) {
                HStack(alignment: .top, spacing: Space.xs) {
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        Text(model.routeTitle).font(.headline)
                        Text(model.routeSummary).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .redacted(reason: model.route == nil && model.isLoading ? .placeholder : [])
                        if model.usesPublicRegistry { Text("Visited in road order").font(.footnote).foregroundStyle(.secondary) }
                    }
                    .padding(.horizontal, Space.m).padding(.vertical, Space.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .glassEffect(.regular, in: .rect(cornerRadius: Radius.card, style: .continuous))
                    .accessibilityElement(children: .combine).accessibilityAddTraits(.isHeader)
                    LazyVGrid(columns: [GridItem(.fixed(48)), GridItem(.fixed(48))], spacing: Space.xs) {
                        Button("Route list", systemImage: "list.number") { showList = true }.disabled(!model.hasRoute)
                        if model.usesPublicRegistry {
                            Button("All flagged kilns", systemImage: "flag") { model.showAllKilns = true }
                                .accessibilityHint("Shows every flagged kiln. The saved plan is kept.")
                        }
                        Button(imagery ? "Standard map" : "Satellite imagery", systemImage: imagery ? "map" : "globe.asia.australia") { imagery.toggle() }
                            .sensoryFeedback(.selection, trigger: imagery)
                        Button("My location", systemImage: "location") {
                            location.recenter()
                            if location.settingsAvailable { showLocationNotice = true }
                        }
                    }
                    .frame(width: 104)
                    .dynamicTypeSize(...DynamicTypeSize.large)
                    .labelStyle(.iconOnly).buttonStyle(.glass).buttonBorderShape(.circle).controlSize(.large)
                }
            }
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            ForEach(Array(banners.prefix(2).enumerated()), id: \.offset) { _, banner in
                QuietBanner(text: banner.text, systemImage: banner.symbol)
            }
        }
        .padding(.horizontal, Space.margin)
    }

    /// Errors and connectivity take priority; at most two banners reserve map space.
    private var banners: [(text: String, symbol: String?)] {
        var result: [(String, String?)] = []
        if let message = model.planner?.failureMessage { result.append((message, "exclamationmark.circle")) }
        if model.isOffline { result.append(("Offline · showing saved route", "wifi.slash")) }
        if let notice = location.notice { result.append((notice, "location")) }
        if case .loaded(_, _, let warning?) = model.routeState { result.append((warning, "exclamationmark.circle")) }
        if let route = model.route, route.hasPassed() {
            result.append(("This plan was for \(route.dayLabel()) · plan again for a new day. Open Route list → Plan again.", "clock"))
        }
        if let route = model.route, route.usableStops.count != route.stops.count {
            result.append(("Some stops have unavailable kiln records", "exclamationmark.circle"))
        }
        if let route = model.route, (route.legs ?? []).allSatisfy({ $0.geometry?.validatedCoordinates.isEmpty != false }) {
            result.append(("Road geometry unavailable · stops still usable", "map"))
        }
        var context: [String] = []
        if model.isPublicDemo, let date = model.savedDate(compact: true) {
            context.append("Sample data · recorded test plan · \(date)")
        } else {
            if let date = model.savedDate() { context.append(date) }
            else if case .saved = model.routeState, !model.usesPublicRegistry { context.append("Saved route · awaiting refresh") }
            if model.isPublicDemo { context.append("Sample data · recorded test plan") }
        }
        if !model.isPublicDemo && (model.isSample || model.demo == .offline || model.demo == .saved) { context.append("Sample data · illustrative routing") }
        if !context.isEmpty { result.append((context.joined(separator: " · "), nil)) }
        return result
    }

    private func carousel(maxHeight: CGFloat) -> some View {
        @Bindable var model = model
        return VStack(spacing: Space.xs) {
            ScrollView(.vertical) {
            ScrollView(.horizontal) {
                LazyHStack(spacing: Space.s) {
                    ForEach(model.stops) { stop in
                        if let kiln = model.kiln(stop.kilnId) {
                            StopCard(stop: stop, kiln: kiln, zoom: zoom)
                            .containerRelativeFrame(.horizontal) { width, _ in max(0, width - Space.margin) }
                            .id(stop.kilnId)
                        }
                    }
                }.scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned).scrollPosition(id: $model.selectedStopId, anchor: .leading)
            .scrollIndicators(.hidden).contentMargins(.horizontal, Space.margin, for: .scrollContent)
            .scrollClipDisabled().fixedSize(horizontal: false, vertical: true)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: .infinity)
            Button(model.routeActive ? "End route" : "Start route") {
                withAnimation(Motion.layout.animation(reduceMotion: reduceMotion)) { model.toggleRoute() }
            }
            .buttonStyle(model.routeActive ? .secondary : .primary).padding(.horizontal, Space.margin)
        }.padding(.bottom, Space.xxs)
            .frame(height: maxHeight)
    }

    private var statePanel: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            switch model.routeState {
            case .loading:
                Label("Loading today's route", systemImage: "map").font(.headline)
                Text("Finding the planned stops and inspection sheets.").font(.subheadline).redacted(reason: .placeholder)
                ProgressView().accessibilityLabel("Loading route")
            case .empty:
                Label("No route planned for today", systemImage: "map").font(.headline)
                Text("Ask the planner to build an inspection route.").font(.subheadline)
                Button("Plan a route") { model.planRouteInAsk() }.buttonStyle(.primary)
            case .failure(let message):
                Label("Route unavailable", systemImage: "exclamationmark.circle").font(.headline)
                Text(message).font(.subheadline)
                Button("Retry") { refresh += 1 }.buttonStyle(.primary)
            default:
                Label("Route records unavailable", systemImage: "questionmark.folder").font(.headline)
                Text("The planned stops have no usable kiln records. Try refreshing the route.").font(.subheadline)
                Button("Retry") { refresh += 1 }.buttonStyle(.primary)
            }
        }
        .foregroundStyle(.ink).frame(maxWidth: .infinity, alignment: .leading)
        .card(floating: true).padding(.horizontal, Space.margin).padding(.bottom, Space.xs)
    }

    private func focus(_ id: String) {
        guard model.stops.contains(where: { $0.kilnId == id }) else { return }
        withAnimation(Motion.select.animation(reduceMotion: reduceMotion)) { model.selectedStopId = id }
    }
    private func fly(to id: String?) {
        guard let id, let kiln = model.kiln(id) else { return }
        framingOverview = false
        moveCamera(.camera(MapCamera(centerCoordinate: kiln.coordinate, distance: 9_000)))
    }
    private func moveCamera(_ target: MapCameraPosition) {
        if reduceMotion { camera = target }
        else { withAnimation(Motion.layout.animation(reduceMotion: false)) { camera = target } }
    }
}

private struct StopCard: View {
    let stop: Stop
    let kiln: Kiln
    let zoom: Namespace.ID
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            NavigationLink(value: stop.kilnId) {
                HStack(alignment: .firstTextBaseline, spacing: Space.xs) {
                    Text(stop.order, format: .number).font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(.inkSecondary)
                    KilnIDLabel(kiln: kiln, showsType: false, idFont: model.usesPublicRegistry ? .footnote.weight(.semibold) : .headline)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(alignment: .top, spacing: Space.xs) {
                NavigationLink(value: stop.kilnId) {
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        Text(model.arrival(for: stop, compact: true)).font(.footnote.monospacedDigit()).foregroundStyle(.inkSecondary)
                            .accessibilityLabel(model.arrival(for: stop, compact: false))
                        Text(typeLine).font(.subheadline.monospacedDigit()).foregroundStyle(.inkSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                Button {
                    model.maps.navigate(id: stop.kilnId, model: model)
                } label: {
                    Label("Navigate", systemImage: "arrow.triangle.turn.up.right.diamond")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.ink)
                        .padding(.horizontal, Space.xs)
                        .frame(minWidth: 44, minHeight: 44)
                        .background(.surface2, in: .capsule)
                        .contentShape(.capsule)
                }
                .accessibilityLabel("Navigate to \(stop.kilnId)")
            }
            NavigationLink(value: stop.kilnId) {
                VStack(alignment: .leading, spacing: Space.xxs) {
                    StopSheetSummary(stop: stop, kiln: kiln)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
                .accessibilityHint("Opens the kiln and its inspection sheet")
            }
        }
        .buttonStyle(.plain)
        .card(floating: true).matchedTransitionSource(id: stop.kilnId, in: zoom)
    }

    private var typeLine: String {
        if model.usesPublicRegistry { return "Predicted \(kiln.type.rawValue) · unverified" }
        let confidence = kiln.typeConfidence.formatted(.number.precision(.fractionLength(2)))
        return "\(kiln.typeIsCertain ? "" : "likely ")\(kiln.type.rawValue) · \(confidence)"
    }
}

/// The plan's inspection sheet for one stop: status, flags measured against thresholds, modelled people and on-site checks.
private struct StopSheetSummary: View {
    let stop: Stop
    let kiln: Kiln
    @Environment(AppModel.self) private var model
    var body: some View {
        StatusBadge(status: model.status(for: kiln), detailed: model.usesPublicRegistry)
        if stop.sheet.rulesFlagged.isEmpty {
            Text("No rule flags measured").font(.subheadline).foregroundStyle(.inkSecondary)
            if let note = kiln.assessmentNote { Text(note).font(.footnote).foregroundStyle(.inkSecondary).fixedSize(horizontal: false, vertical: true) }
        } else {
            ForEach(stop.sheet.rulesFlagged, id: \.self) { rule in
                let line = kiln.violations.first { $0.ruleId == rule }.map { $0.compactLine(for: kiln) } ?? "Measurement unavailable"
                Text("\(Text(rule).monospaced()) · \(line)").font(.subheadline.monospacedDigit()).foregroundStyle(.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        Text("\(stop.sheet.peopleExposed.grouped) people within 800 m\(model.usesPublicRegistry ? " · modelled" : "")")
            .font(.subheadline.monospacedDigit()).foregroundStyle(.inkSecondary)
        if !stop.sheet.onSiteChecks.isEmpty {
            Text("Check on site: \(stop.sheet.onSiteChecks.joined(separator: " · "))").font(.footnote).foregroundStyle(.inkSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct QuietBanner: View {
    let text: String
    let systemImage: String?
    var body: some View {
        HStack(spacing: Space.xxs) {
            if let systemImage { Image(systemName: systemImage).accessibilityHidden(true) }
            Text(text)
        }
        .font(.footnote.weight(.medium)).foregroundStyle(.inkSecondary)
        .padding(.horizontal, Space.s).padding(.vertical, Space.xxs).background(.surface, in: .capsule)
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }
}

private struct RouteListSheet: View {
    let select: (String) -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var detent: PresentationDetent = .medium
    var body: some View {
        NavigationStack {
            List {
                if let planner = model.planner {
                    Section {
                        Button { model.planRoute() } label: {
                            if planner.isPlanning { Label { Text("Planning") } icon: { ProgressView() } }
                            else { Label("Plan again", systemImage: "arrow.clockwise") }
                        }
                        .disabled(!planner.canPlan())
                        .accessibilityHint("Sends one plan request. It counts toward a shared daily limit.")
                        if let message = planner.failureMessage {
                            Label(message, systemImage: "exclamationmark.circle").font(.subheadline).foregroundStyle(.ink)
                        }
                    } footer: {
                        Text("A new plan replaces this one only if it succeeds.")
                    }
                }
                Section {
                    ForEach(model.stops) { stop in
                        if let kiln = model.kiln(stop.kilnId) {
                            Button { select(stop.kilnId) } label: {
                                VStack(alignment: .leading, spacing: Space.xs) {
                                    let layout = typeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading)) : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
                                    layout {
                                        Text(stop.order, format: .number).font(.body.weight(.semibold).monospacedDigit()).foregroundStyle(.inkSecondary)
                                        KilnIDLabel(kiln: kiln, idFont: model.usesPublicRegistry ? .footnote.weight(.semibold) : .headline, predictionOnly: model.usesPublicRegistry)
                                    }
                                    Text(model.arrival(for: stop, compact: false)).font(.footnote.monospacedDigit()).foregroundStyle(.inkSecondary)
                                    StopSheetSummary(stop: stop, kiln: kiln)
                                    if let note = stop.access?.note { Text(note).font(.footnote).foregroundStyle(.inkSecondary) }
                                    if stop.access?.coordinate.isValid != true { Text("No access point · Navigate will ask before using the kiln location").font(.footnote).foregroundStyle(.inkSecondary) }
                                }.padding(.vertical, Space.xxs)
                            }
                            .buttonStyle(.plain).accessibilityElement(children: .combine)
                            .accessibilityHint("Selects this stop on the map")
                            .accessibilityAddTraits(model.selectedStopId == stop.kilnId ? .isSelected : [])
                        }
                    }
                } header: {
                    Text("Visited in road order")
                } footer: {
                    Text(model.usesPublicRegistry
                         ? "Stops were chosen by most people within 800 m, then ordered by driving time. Arrival times and totals are estimates. Opening Maps does not complete an inspection. \(Exposure.attribution)"
                         : "Stop order is supplied with the plan. Arrival times are estimates. Opening Maps does not complete an inspection.")
                }
                if let notes = model.route?.notes, !notes.isEmpty {
                    Section("Plan notes") {
                        ForEach(Array(notes.enumerated()), id: \.offset) { _, note in Text(note).font(.subheadline).foregroundStyle(.ink) }
                    }
                }
                Section {
                    Button("Open whole route in Maps", systemImage: "arrow.triangle.turn.up.right.diamond") { model.maps.wholeRoute(model: model) }
                        .disabled(!model.hasRoute)
                } footer: {
                    Text("Opens the remaining stops in plan order. Offline navigation depends on Maps and any downloaded region.")
                }
                if model.isSample || model.demo == .offline || model.demo == .saved {
                    Text("Sample access points and linework are illustrative. Confirm entrances on site.").font(.footnote).foregroundStyle(.inkSecondary)
                }
            }
            .navigationTitle("Route · \(model.stops.count) stops").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Close", systemImage: "xmark", role: .close) { dismiss() } } }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .onChange(of: typeSize, initial: true) { _, size in
            if size.isAccessibilitySize { detent = .large }
        }
    }
}

#Preview { TodayView().environment(AppModel(useFixtures: true)) }
