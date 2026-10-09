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
enum DemoState: String { case live, loading, empty, offline }

@MainActor @Observable
final class AppModel {
    var signedIn: Bool
    var tab: AppTab
    var demo: DemoState
    private(set) var kilns: [String: Kiln]
    let stops = Mock.stops
    var routeActive: Bool
    var currentStop = 0
    var todayPath: [String] = []
    var kilnsPath: [String] = []
    var askPath: [String] = []
    var askDraft = ""
    var shownRule: Rule?

    var isOffline: Bool { demo == .offline }
    var isLoading: Bool { demo == .loading }
    var hasRoute: Bool { demo != .empty }
    var allKilns: [Kiln] { Mock.registry.compactMap { kilns[$0.kilnID] } }

    init() {
        kilns = Dictionary(uniqueKeysWithValues: Mock.registry.map { ($0.kilnID, $0) })
        let defaults = UserDefaults.standard
        signedIn = defaults.bool(forKey: "signedIn")
        tab = AppTab(rawValue: defaults.string(forKey: "tab") ?? "") ?? .today
        demo = DemoState(rawValue: defaults.string(forKey: "demo") ?? "") ?? .live
        routeActive = defaults.bool(forKey: "routeActive")
        if let id = defaults.string(forKey: "open") { open(kiln: id) }
        shownRule = defaults.string(forKey: "rule").map(Rule.named)
    }

    func kiln(_ id: String) -> Kiln { kilns[id] ?? Mock.route[0] }

    func stopNumber(for id: String) -> Int? { stops.first { $0.kilnID == id }?.number }

    /// The only way a kiln's status changes.
    func recordVerdict(_ status: KilnStatus, for id: String) {
        kilns[id]?.status = status
    }

    /// Pushes a kiln onto the current tab's stack (citation chips, rows).
    func open(kiln id: String) {
        switch tab {
        case .today: todayPath.append(id)
        case .kilns: kilnsPath.append(id)
        case .ask: askPath.append(id)
        }
    }

    /// The route accessory: jump to Today and show the current stop.
    func openCurrentStop() {
        tab = .today
        todayPath = [stops[currentStop].kilnID]
    }

    func planRouteInAsk() {
        askDraft = "Plan tomorrow in Hapur. Six hours. Schools first."
        tab = .ask
    }

    func handle(_ url: URL) -> OpenURLAction.Result {
        guard url.scheme == "kilnwatch" else { return .systemAction }
        let id = url.lastPathComponent
        if url.host() == "kiln" { open(kiln: id) } else { shownRule = Rule.named(id) }
        return .handled
    }
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
        .tabViewBottomAccessory(isEnabled: model.routeActive) { RouteAccessory() }
    }
}

/// "Stop 1 of 9 · KW-0412 · 14 min", like the Music now-playing bar. Tapping opens the stop.
private struct RouteAccessory: View {
    @Environment(AppModel.self) private var model
    @Environment(\.tabViewBottomAccessoryPlacement) private var placement
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let stop = model.stops[model.currentStop]
        Button { model.openCurrentStop() } label: {
            HStack(spacing: Space.xs) {
                Image(systemName: "car.fill")
                    .foregroundStyle(.clay)
                    .accessibilityHidden(true)
                if placement == .inline || typeSize > .large {
                    Text("\(Text(stop.kilnID).monospaced()) · \(stop.driveMinutes) min")
                } else {
                    Text("Stop \(stop.number) of \(model.stops.count) · \(Text(stop.kilnID).monospaced()) · \(stop.driveMinutes) min")
                }
            }
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .lineLimit(1)
            .dynamicTypeSize(...DynamicTypeSize.xxLarge)
            .padding(.horizontal, Space.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Stop \(stop.number) of \(model.stops.count), \(stop.kilnID), \(stop.driveMinutes) minutes away")
        .accessibilityHint("Opens the kiln")
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
                    }
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        Text("Legal source").eyebrow()
                        Text(rule.source).font(.body).foregroundStyle(.ink)
                    }
                    Text("Thresholds as compiled in the Space to Policy study, checked against the gazette text.")
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
