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
    private(set) var kilns: [String: Kiln]
    private var verdictOverrides: [String: KilnStatus] = [:]
    private(set) var routeState: TodayRouteState = .loading
    private(set) var routeActive = false
    private(set) var currentStopId: String?
    var selectedStopId: String?
    var todayPath: [String] = []
    var kilnsPath: [String] = []
    var askPath: [String] = []
    var askDraft = ""
    var shownRule: Rule?
    let maps = MapsHandoff()
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
    var isLoading: Bool { if case .loading = routeState { return true }; return false }
    var hasRoute: Bool { !stops.isEmpty }
    var isSample: Bool { if case .loaded(_, sample: true, _) = routeState { return true }; return false }
    var allKilns: [Kiln] { kilns.values.sorted { $0.kilnId < $1.kilnId } }

    init(api: KilnWatchAPI? = nil) {
        let environment = ProcessInfo.processInfo.environment
        if let api { self.api = api }
        else if let address = environment["KILNWATCH_API_URL"], let url = URL(string: address),
                url.scheme == "https", let host = url.host, !host.hasSuffix(".example"),
                let token = environment["KILNWATCH_API_TOKEN"], !token.isEmpty {
            self.api = KilnWatchAPI(baseURL: url, token: { token })
        } else { self.api = nil }
        kilns = self.api == nil ? Dictionary(Fixtures.kilns.map { ($0.kilnId, $0) }, uniquingKeysWith: { _, new in new }) : [:]
        signedIn = DemoOptions.bool("signedIn")
        tab = AppTab(rawValue: DemoOptions.string("tab") ?? "") ?? .today
        demo = DemoState(rawValue: DemoOptions.string("demo") ?? "") ?? .live
        cache = demo == .live ? RouteCache() : RouteCache(directory: URL.kilnWatchStore.appending(path: "DebugRouteCache"))
        if let id = DemoOptions.string("open") { open(kiln: id) }
        shownRule = DemoOptions.string("rule").map(Rule.named)
    }

    func kiln(_ id: String) -> Kiln? { kilns[id] }
    func usesIllustrativeEvidence(for kiln: Kiln) -> Bool {
        api == nil && Fixtures.kilns.contains(kiln)
    }
    func status(for kiln: Kiln) -> KilnStatus { verdictOverrides[kiln.kilnId] ?? kiln.status }
    func stopNumber(for id: String) -> Int? { stops.first { $0.kilnId == id }?.order }
    func recordVerdict(_ status: KilnStatus, for id: String) {
        guard kilns[id] != nil else { return }
        verdictOverrides[id] = status // Mock presentation only; wire record remains immutable.
    }

    func loadRoute(force: Bool = false) async {
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
            #if DEBUG
            apply(.loaded(Fixtures.route, sample: true, warning: nil))
            #else
            if route == nil { apply(.failure("Route service is not configured. Contact your department.")) }
            #endif
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
            for kiln in route.kilns { kilns[kiln.kilnId] = kiln }
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
    func planRouteInAsk() {
        askDraft = "Plan today's inspection route. Leave the office at 9. Six hours. Schools first."
        tab = .ask
    }
    func handle(_ url: URL) -> OpenURLAction.Result {
        guard url.scheme == "kilnwatch" else { return .systemAction }
        let id = url.lastPathComponent
        if url.host() == "kiln" { open(kiln: id) } else { shownRule = Rule.named(id) }
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
        .sheet(item: $model.shownRule) { RuleSheet(rule: $0) }
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
        .task { await model.loadRoute() }
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
                    if placement == .inline || typeSize > .large {
                        Text("\(stop.kilnId) · \(model.timing(for: stop))").monospacedDigit()
                    } else {
                        Text("Stop \(stop.order) of \(model.stops.count) · \(stop.kilnId) · \(model.timing(for: stop))")
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
            .accessibilityLabel("Current stop \(stop.order) of \(model.stops.count), \(stop.kilnId), \(model.timing(for: stop))")
            .accessibilityHint("Opens the kiln")
        }
    }
}

/// A rule from the catalog, opened from a citation chip.
struct RuleSheet: View {
    let rule: Rule
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.m) {
                    Text(rule.id)
                        .font(.title.weight(.semibold).monospaced())
                        .foregroundStyle(.ink)
                    Text(rule.name)
                        .font(.headline)
                        .foregroundStyle(.ink)
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        Text("Check").eyebrow()
                        Text(rule.check).font(.body).foregroundStyle(.ink)
                        if let threshold = rule.thresholdM { Text("Catalog threshold: \(Int(threshold).grouped) m").font(.body).foregroundStyle(.ink) }
                        if let requirement = rule.requirement { Text(requirement).font(.body).foregroundStyle(.ink) }
                        ForEach(rule.overrides, id: \.state) { override in
                            Text("\(override.state): \(Int(override.thresholdM).grouped) m").font(.body).foregroundStyle(.ink)
                        }
                    }
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        Text("Legal source").eyebrow()
                        Text(rule.source).font(.body).foregroundStyle(.ink)
                    }
                    Text("Policy compilation from the Space to Policy study. Rule IDs and applied thresholds await backend confirmation.")
                        .font(.footnote)
                        .foregroundStyle(.inkSecondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Space.margin)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark", role: .close) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}
