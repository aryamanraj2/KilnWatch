import AppIntents
import KilnWatchCore
import SwiftUI

@main
struct KilnWatchApp: App {
    @State private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(model)
        }
    }
}

enum AppTab: String, Hashable { case today, kilns, ask }

/// Demo states for the clickable mock, set with launch arguments (`-demo loading|empty|offline`).
/// Other launch arguments: `-signedIn YES`, `-tab kilns`, `-open KW-0412`, `-routeActive YES`, `-rule C-HAB-800`,
/// `-query KW-09`, `-routeList YES`, `-imagery YES`, `-askPlay YES`; DEBUG only: `-scroll rules`, `-verdict YES`,
/// `-verdictChoice confirmed`, `-autoplay carousel|hold`.
enum DemoState: String { case live, loading, empty, offline, failure, noCache, corruptCache, saved, missingGeometry }

enum RegistryState {
    case loading, loaded, empty, offline, busy(retrying: Bool), unavailable, notFound, failure, interrupted

    var message: String {
        switch self {
        case .loading: "Loading satellite records"
        case .loaded: ""
        case .empty: "No flagged kilns"
        case .offline: "You're offline"
        case .busy: "Busy, retrying"
        case .unavailable: "KilnWatch data is temporarily unavailable"
        case .notFound: "Kiln not found"
        case .failure: "The records could not be loaded"
        case .interrupted: "Loading interrupted"
        }
    }
}

enum TodayRouteState {
    case loading
    case loaded(Route, sample: Bool, warning: String?)
    case saved(Route, offline: Bool)
    case empty
    case failure(String)

    var route: Route? {
        switch self {
        case .loaded(let route, _, _), .saved(let route, _): route
        default: nil
        }
    }
}

/// Launch overrides never affect a release build.
enum DemoOptions {
    static func string(_ key: String) -> String? {
        #if DEBUG
        UserDefaults.standard.string(forKey: key)
        #else
        nil
        #endif
    }
    static func bool(_ key: String) -> Bool { string(key)?.lowercased() == "yes" }
}

@MainActor @Observable
final class AppModel {
    var signedIn: Bool
    var tab: AppTab
    let demo: DemoState
    let district: String
    let usesPublicRegistry: Bool
    let isPublicDemo: Bool
    private let publicAPI: KilnWatchAPI?
    private(set) var registryState: RegistryState = .loading
    private(set) var registryRefreshing = false
    private var didLoadRegistry = false
    private(set) var detailStates: [String: RegistryState] = [:]
    private var detailRecords: [String: Kiln] = [:]
    private var detailRefreshing: Set<String> = []
    private(set) var kilns: [String: Kiln]
    private var verdictOverrides: [String: KilnStatus] = [:]
    private(set) var routeState: TodayRouteState = .loading
    private(set) var routeActive = false
    private(set) var currentStopId: String?
    var selectedStopId: String?
    var todayPath: [String] = []
    var kilnsPath: [String] = []
    var askPath: [String] = []
    let ask: AskConversation
    let askConnectivity: AskConnectivity
    var askDraft: String {
        get { ask.draft }
        set { ask.draft = newValue }
    }
    var isAskTest: Bool { DemoOptions.string("askDemo") != nil }
    var shownRule: RuleReference?
    let maps = MapsHandoff()
    /// Live public mode only. Plans on an explicit tap, never on launch, tab switch or foreground.
    let planner: RoutePlanner?
    /// Browsing every flagged kiln while keeping the saved plan.
    var showAllKilns = false
    private let api: KilnWatchAPI?
    private let cache: RouteCache
    private var didLoadRoute = false
    private var refreshing = false

    var route: Route? { routeState.route }
    var stops: [Stop] { route?.usableStops ?? [] }
    var currentStop: Stop? { stops.first { $0.kilnId == currentStopId } }
    var isOffline: Bool {
        if case .saved(_, offline: true) = routeState { return true }
        return false
    }
    var isLoading: Bool {
        if usesPublicRegistry { if case .loading = registryState { return true }; return false }
        if case .loading = routeState { return true }; return false
    }
    var hasRoute: Bool { !stops.isEmpty }
    var isSample: Bool { if case .loaded(_, sample: true, _) = routeState { return true }; return false }
    var allKilns: [Kiln] { kilns.values.sorted { $0.kilnId < $1.kilnId } }

    init(api: KilnWatchAPI? = nil, useFixtures: Bool = false) {
        let environment = ProcessInfo.processInfo.environment
        district = (Bundle.main.object(forInfoDictionaryKey: "KilnWatchDistrict") as? String).flatMap { $0.isEmpty ? nil : $0 } ?? "Hapur"
        var configuredPublic: KilnWatchAPI?
        if !useFixtures && !DemoOptions.bool("fixtures"),
           let address = Bundle.main.object(forInfoDictionaryKey: "KilnWatchPublicAPIURL") as? String,
           let url = URL(string: address), url.scheme == "https", let host = url.host, !host.isEmpty {
            configuredPublic = KilnWatchAPI(baseURL: url, session: KilnWatchAPI.publicReadSession())
        }
        #if DEBUG
        if !useFixtures, let scenario = DemoOptions.string("publicDemo") ?? (DemoOptions.string("askDemo") != nil || DemoOptions.string("rulesDemo") != nil || DemoOptions.string("planDemo") != nil ? "loaded" : nil) {
            configuredPublic = PublicDemo.api(scenario: scenario)
            isPublicDemo = true
        } else { isPublicDemo = false }
        #else
        isPublicDemo = false
        #endif
        ask = AskConversation(api: configuredPublic)
        askConnectivity = AskConnectivity(observing: configuredPublic != nil && !isPublicDemo)
        publicAPI = configuredPublic
        usesPublicRegistry = configuredPublic != nil
        if let api { self.api = api }
        else if let address = environment["KILNWATCH_API_URL"], let url = URL(string: address),
                url.scheme == "https", let host = url.host, !host.hasSuffix(".example"),
                let token = environment["KILNWATCH_API_TOKEN"], !token.isEmpty {
            self.api = KilnWatchAPI(baseURL: url, token: { token })
        } else { self.api = nil }
        kilns = configuredPublic == nil && self.api == nil ? Dictionary(Fixtures.kilns.map { ($0.kilnId, $0) }, uniquingKeysWith: { _, new in new }) : [:]
        signedIn = usesPublicRegistry || DemoOptions.bool("signedIn")
        tab = AppTab(rawValue: DemoOptions.string("tab") ?? "") ?? .today
        demo = DemoState(rawValue: DemoOptions.string("demo") ?? "") ?? .live
        // Public plans never share a file with the signed-in route; test plans never touch the live saved plan.
        let routeCache = usesPublicRegistry ? RouteCache(directory: URL.kilnWatchStore.appending(path: isPublicDemo ? "DebugPublicPlan" : "PublicPlan"))
            : demo == .live ? RouteCache() : RouteCache(directory: URL.kilnWatchStore.appending(path: "DebugRouteCache"))
        cache = routeCache
        #if DEBUG
        if isPublicDemo && DemoOptions.bool("resetPlan") { try? routeCache.clear() } // Test plans only; never the live saved plan.
        #endif
        let planDistrict = district
        planner = configuredPublic.map { RoutePlanner(api: $0, district: planDistrict, cache: routeCache) }
        if let id = DemoOptions.string("open") { open(kiln: id) }
        shownRule = DemoOptions.string("rule").map(RuleReference.catalog)
    }

    func kiln(_ id: String) -> Kiln? { detailRecords[id] ?? kilns[id] ?? route?.kilns.first { $0.kilnId == id } }
    func usesIllustrativeEvidence(for kiln: Kiln) -> Bool {
        !usesPublicRegistry && api == nil && Fixtures.kilns.contains(kiln)
    }
    func status(for kiln: Kiln) -> KilnStatus { verdictOverrides[kiln.kilnId] ?? kiln.status }
    func stopNumber(for id: String) -> Int? { stops.first { $0.kilnId == id }?.order }
    func recordVerdict(_ status: KilnStatus, for id: String) {
        guard !usesPublicRegistry, kilns[id] != nil else { return }
        verdictOverrides[id] = status // Mock presentation only; wire record remains immutable.
    }

    var dataSourceLabel: String { usesPublicRegistry && !isPublicDemo ? "Live data" : "Sample data" }
    func isRefreshingDetail(_ id: String) -> Bool { detailRefreshing.contains(id) }

    func loadData() async {
        if usesPublicRegistry { await loadSavedPlan(); await loadRegistry() }
        else { await loadRoute() }
    }

    /// Disk only: launch shows the saved plan, if any, and never sends a plan request.
    private func loadSavedPlan() async {
        guard !didLoadRoute else { return }
        didLoadRoute = true
        do {
            if let saved = try await RouteRefresh.saved(in: cache), !saved.stops.isEmpty { apply(.saved(saved, offline: false)) }
            else { routeState = .empty }
        } catch { routeState = .failure("The saved plan could not be read. Plan again to replace it.") }
    }

    /// One user-initiated plan. A failure keeps whatever plan is showing.
    func planRoute() {
        guard let planner, planner.canPlan() else { return }
        Task {
            if let result = await planner.plan() {
                showAllKilns = false
                apply(.loaded(result.route, sample: false, warning: result.cacheWarning))
            } else if case .transport? = planner.failure, let route {
                apply(.saved(route, offline: true))
            }
        }
    }

    private func syncSavedPlanConnectivity() {
        guard usesPublicRegistry, case .saved(let route, let offline) = routeState else { return }
        let registryOffline = if case .offline = registryState { true } else { false }
        if registryOffline != offline { routeState = .saved(route, offline: registryOffline) }
    }

    func loadRegistry(force: Bool = false) async {
        guard let publicAPI, !registryRefreshing, force || !didLoadRegistry else { return }
        registryRefreshing = true
        registryState = .loading
        defer { syncSavedPlanConnectivity() }
        // No saved registry: every failed refresh has an honest state instead of stale counts.
        kilns = [:]
        defer { registryRefreshing = false }
        #if DEBUG
        if DemoOptions.string("publicDemo") == "loading" { return }
        #endif
        guard let result = await publicRead(state: { registryState = $0 }, operation: { () async throws(APIError) -> [Kiln] in
            try await publicAPI.publicKilns(district: district)
        }) else { return }
        kilns = Dictionary(result.map { ($0.kilnId, $0) }, uniquingKeysWith: { _, new in new })
        registryState = result.isEmpty ? .empty : .loaded
        didLoadRegistry = true
    }

    func loadDetail(_ id: String, force: Bool = false) async {
        guard let publicAPI, !detailRefreshing.contains(id) else { return }
        if !force, case .loaded = detailStates[id] { return }
        detailRefreshing.insert(id)
        detailStates[id] = .loading
        defer { detailRefreshing.remove(id) }
        guard let record = await publicRead(state: { detailStates[id] = $0 }, operation: { () async throws(APIError) -> Kiln in
            try await publicAPI.publicKiln(id: id)
        }) else { return }
        guard record.kilnId == id else { detailStates[id] = .failure; return }
        detailRecords[id] = record
        detailStates[id] = .loaded
    }

    /// One bounded automatic backoff for throttling; view tasks own cancellation.
    private func publicRead<T>(state: (RegistryState) -> Void, operation: () async throws(APIError) -> T) async -> T? {
        for attempt in 0...1 {
            do {
                let result = try await operation()
                guard !Task.isCancelled else { state(.interrupted); return nil }
                return result
            } catch {
                guard !Task.isCancelled else { state(.interrupted); return nil }
                switch error {
                case .status(429, _) where attempt == 0:
                    state(.busy(retrying: true))
                    do { try await Task.sleep(for: .seconds(2)) } catch { state(.interrupted); return nil }
                case .status(429, _): state(.busy(retrying: false)); return nil
                case .status(503, _): state(.unavailable); return nil
                case .status(404, _): state(.notFound); return nil
                case .transport: state(.offline); return nil
                default: state(.failure); return nil
                }
            }
        }
        return nil
    }

    func loadRoute(force: Bool = false) async {
        guard !usesPublicRegistry else { return }
        guard !refreshing, force || !didLoadRoute else { return }
        refreshing = true
        defer { refreshing = false }
        #if DEBUG
        if demo != .live {
            do {
                switch demo {
                case .loading: routeState = .loading
                case .empty: apply(.empty)
                case .failure: apply(.failure("The route service returned 503. Try again."))
                case .noCache: apply(.failure("No connection and no saved route. Try again when you have a signal."))
                case .corruptCache:
                    try await Self.corruptDebugCache(cache)
                    _ = try await RouteRefresh.saved(in: cache)
                case .offline:
                    try await Self.seedDebugCache(cache)
                    if let saved = try await RouteRefresh.saved(in: cache) { apply(.saved(saved, offline: true)) }
                case .saved:
                    if let saved = try await RouteRefresh.saved(in: cache) { apply(.saved(saved, offline: true)) }
                    else { apply(.failure("No saved sample route. Run the offline demonstration first.")) }
                case .missingGeometry:
                    let r = Fixtures.route
                    apply(.loaded(Route(district: r.district, generatedAt: r.generatedAt, stops: r.stops, kilns: r.kilns,
                                        routeId: r.routeId, depart: r.depart, budgetMin: r.budgetMin), sample: true, warning: nil))
                case .live: break
                }
            } catch { apply(.failure("The saved route could not be read. Reconnect and retry.")) }
            didLoadRoute = true
            return
        }
        #endif
        do {
            if let saved = try await RouteRefresh.saved(in: cache), !saved.stops.isEmpty {
                try Task.checkCancellation()
                apply(.saved(saved, offline: false))
            }
        } catch is CancellationError { return }
        catch { routeState = .failure("The saved route could not be read. Reconnect and retry.") }
        guard let api else {
            apply(.loaded(Fixtures.route, sample: true, warning: nil))
            didLoadRoute = true
            return
        }
        do {
            let result = try await RouteRefresh.fetch(using: api, cache: cache)
            try Task.checkCancellation()
            switch result {
            case .loaded(let route, let warning): apply(.loaded(route, sample: false, warning: warning))
            case .empty: apply(.empty)
            case .offline(let route): apply(.saved(route, offline: true))
            case .failure(let message): apply(.failure(message))
            }
            didLoadRoute = true
        } catch is CancellationError { return }
        catch { apply(.failure("The route could not be refreshed. Try again.")) }
    }

    private func apply(_ state: TodayRouteState) {
        let previous = route
        routeState = state
        let available = stops
        if let route {
            // Public plans read their own embedded records; the registry list stays the registry.
            if !usesPublicRegistry { for kiln in route.kilns { kilns[kiln.kilnId] = kiln } }
            if let previous, previous.routeId != route.routeId || previous.generatedAt != route.generatedAt {
                routeActive = false; currentStopId = nil
            }
        }
        if !available.contains(where: { $0.kilnId == selectedStopId }) { selectedStopId = available.first?.kilnId }
        if !available.contains(where: { $0.kilnId == currentStopId }) { currentStopId = nil; routeActive = false }
        #if DEBUG
        if !didLoadRoute, DemoOptions.bool("routeActive"), let first = available.first {
            routeActive = true; currentStopId = first.kilnId
        }
        if let selected = DemoOptions.string("selected"), available.contains(where: { $0.kilnId == selected }), !didLoadRoute {
            selectedStopId = selected
        }
        #endif
    }

    func toggleRoute() {
        if routeActive { routeActive = false; currentStopId = nil }
        else if let first = stops.first { currentStopId = first.kilnId; routeActive = true }
    }

    func open(kiln id: String) {
        switch tab {
        case .today: todayPath.append(id)
        case .kilns: kilnsPath.append(id)
        case .ask: askPath.append(id)
        }
    }
    func openCurrentStop() {
        guard let stop = currentStop else { return }
        tab = .today; selectedStopId = stop.kilnId; todayPath = [stop.kilnId]
    }
    func askAboutKiln(_ id: String) {
        ask.prefill(kilnId: id)
        askPath = []
        tab = .ask
    }
    func planRouteInAsk() {
        guard !usesPublicRegistry else { return }
        askDraft = "Plan today's inspection route. Leave the office at 9. Six hours. Schools first."
        tab = .ask
    }
    func handle(_ url: URL) -> OpenURLAction.Result {
        guard url.scheme == "kilnwatch" else { return .systemAction }
        let id = url.lastPathComponent
        if url.host() == "kiln" { open(kiln: id) } else { shownRule = .catalog(id) }
        return .handled
    }

    #if DEBUG
    @concurrent private static func seedDebugCache(_ cache: RouteCache) async throws { try cache.save(Fixtures.route) }
    @concurrent private static func corruptDebugCache(_ cache: RouteCache) async throws {
        try FileManager.default.createDirectory(at: cache.fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("broken sample cache".utf8).write(to: cache.fileURL, options: .atomic)
    }
    #endif
}

struct RootView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        ZStack {
            if model.signedIn {
                MainTabs().transition(.opacity)
            } else {
                SignInView().transition(.opacity)
            }
        }
        .environment(\.openURL, OpenURLAction { model.handle($0) })
        .sheet(item: $model.shownRule) { RuleSheet(reference: $0) }
        .alert("Use kiln location?", isPresented: Binding(get: { model.maps.confirmation != nil }, set: { if !$0 { model.maps.cancel() } })) {
            Button("Open Maps") { model.maps.openPending() }
            Button("Cancel", role: .cancel) { model.maps.cancel() }
        } message: { Text(model.maps.confirmation ?? "") }
        .alert("Maps unavailable", isPresented: Binding(get: { model.maps.error != nil }, set: { if !$0 { model.maps.error = nil } })) {
            Button("Close", role: .cancel) { model.maps.error = nil }
        } message: { Text(model.maps.error ?? "") }
    }
}

private struct MainTabs: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        TabView(selection: $model.tab) {
            Tab("Today", systemImage: "map", value: AppTab.today) { TodayView() }
            Tab("Kilns", systemImage: "list.bullet", value: AppTab.kilns) { KilnsView() }
            Tab("Ask", systemImage: "text.bubble", value: AppTab.ask) { AskView() }
        }
        .tabBarMinimizeBehavior(.onScrollDown)
        .task { await model.loadData() }
        .tabViewBottomAccessory(isEnabled: model.routeActive && model.currentStop != nil) { RouteAccessory() }
    }
}

/// "Stop 1 of 9 · KW-0412 · 14 min", like the Music now-playing bar. Tapping opens the stop.
private struct RouteAccessory: View {
    @Environment(AppModel.self) private var model
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        if let stop = model.currentStop {
            Button { model.openCurrentStop() } label: {
                HStack(spacing: Space.xs) {
                    Image(systemName: "car.fill").foregroundStyle(.clay).accessibilityHidden(true)
                    // Full registry IDs never truncate, so a long ID stays in the spoken label and the stop.
                    let shortID = stop.kilnId.count <= 12 ? stop.kilnId : nil
                    if placement == .inline || typeSize > .large {
                        Text("\(shortID ?? "Stop \(stop.order)") · Est. \(Route.clock(stop.eta))").monospacedDigit()
                    } else {
                        Text("Stop \(stop.order) of \(model.stops.count) · \(shortID.map { "\($0) · " } ?? "")\(model.arrival(for: stop, compact: true))")
                    }
                }
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
                .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                .padding(.horizontal, Space.m)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Current stop \(stop.order) of \(model.stops.count), \(stop.kilnId), \(model.arrival(for: stop, compact: false))")
            .accessibilityHint("Opens the kiln")
        }
    }
}

/// A rule from the catalog, opened from a citation chip.
struct RuleSheet: View {
    let reference: RuleReference
    private var rule: Rule { reference.rule }
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.m) {
                    Text(rule.id)
                        .font(.title.weight(.semibold).monospaced())
                        .foregroundStyle(.ink)
                    Text(reference.check?.check ?? rule.name)
                        .font(.headline)
                        .foregroundStyle(.ink)
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        Text("Check").eyebrow()
                        if let kilnId = reference.kilnId {
                            Text(kilnId).font(.footnote.monospaced()).foregroundStyle(.inkSecondary)
                                .typesettingLanguage(.explicit(.init(identifier: "zxx")))
                        }
                        if let check = reference.check {
                            Text(check.status.label).font(.body).foregroundStyle(.ink)
                            Text(check.measurementLine).font(.body.monospacedDigit()).foregroundStyle(.ink)
                            if let flag = reference.flag,
                               flag.measuredDistanceM != check.measuredDistanceM || flag.thresholdM != check.thresholdM || check.status != .withinThreshold {
                                Text("Supplied flag: \(flag.compactLine(for: nil)). Flag and check differ; inspect on site.")
                                    .font(.footnote).foregroundStyle(.inkSecondary)
                            }
                        } else if let flag = reference.flag {
                            Text("Siting flag · needs inspection").font(.body).foregroundStyle(.ink)
                            Text(flag.compactLine(for: nil)).font(.body.monospacedDigit()).foregroundStyle(.ink)
                        } else {
                            Text(rule.check).font(.body).foregroundStyle(.ink)
                            if let threshold = RuleCheck.metres(rule.thresholdM) { Text("Reference threshold: \(threshold)").font(.body).foregroundStyle(.ink) }
                            if let requirement = rule.requirement { Text("Reference requirement: \(requirement)").font(.body).foregroundStyle(.ink) }
                            Text("Reference only. No kiln measurement or check result supplied.").font(.footnote).foregroundStyle(.inkSecondary)
                        }
                    }
                    ThresholdWarning(verification: reference.verification)
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        Text("Threshold source").eyebrow()
                        Text(reference.check?.source ?? reference.flag?.source ?? rule.source).font(.body).foregroundStyle(.ink)
                        if let check = reference.check, let flag = reference.flag, flag.source != check.source {
                            Text("Supplied flag source: \(flag.source)").font(.footnote).foregroundStyle(.inkSecondary)
                        }
                    }
                    Text(reference.verification?.explanation ?? "Threshold verification unavailable.")
                        .font(.footnote)
                        .foregroundStyle(.inkSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.margin)
            }
            .navigationTitle("Rule source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark", role: .close) { dismiss() }
                }
            }
        }
        .presentationDetents(typeSize.isAccessibilitySize ? [.large] : [.medium, .large])
    }
}
