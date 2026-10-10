import KilnWatchCore
import SwiftUI

/// The searchable registry.
struct KilnsView: View {
    @Environment(AppModel.self) private var model
    @Namespace private var zoom
    @State private var query = DemoOptions.string("query") ?? ""
    @State private var status: KilnStatus?
    @State private var district = "Hapur"

    private var districts: [String] {
        model.usesPublicRegistry ? [model.district] : Array(Set(model.allKilns.map { $0.district ?? "District unavailable" })).sorted()
    }
    private var results: [Kiln] {
        model.allKilns.filter { kiln in
            (model.usesPublicRegistry || (kiln.district ?? "District unavailable") == district)
                && (status == nil || model.status(for: kiln) == status)
                && (query.isEmpty
                    || kiln.kilnId.localizedStandardContains(query)
                    || kiln.violations.contains { $0.ruleId.localizedStandardContains(query) })
        }
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.kilnsPath) {
            List {
                Section {
                    ForEach(results) { kiln in
                        NavigationLink(value: kiln.kilnId) { KilnRow(kiln: kiln) }
                            .matchedTransitionSource(id: kiln.kilnId, in: zoom)
                            .listRowBackground(Color.surface)
                    }
                } header: {
                    if !results.isEmpty {
                        VStack(alignment: .leading, spacing: Space.xs) {
                            Text("\(model.usesPublicRegistry ? model.district : district) · \(results.count) kilns").eyebrow()
                            if results.contains(where: { $0.exposure != nil }) {
                                Text(model.usesPublicRegistry && (!model.isPublicDemo || DemoOptions.string("rulesDemo") == "recorded")
                                     ? Exposure.attribution : "Sample population figures · illustrative, not an HRSL calculation")
                                    .font(.footnote).foregroundStyle(.inkSecondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .textCase(nil)
                    }
                }
            }
            .scrollEdgeEffectStyle(.hard, for: .top)
            .scrollContentBackground(.hidden)
            .background(.canvas)
            .redacted(reason: model.isLoading ? .placeholder : [])
            .overlay {
                if model.usesPublicRegistry, !registryLoaded {
                    ScrollView {
                        RegistryStateView(state: model.registryState, district: model.district,
                                          retrying: model.registryRefreshing) { await model.loadRegistry(force: true) }
                    }
                    .background(.canvas)
                } else if results.isEmpty {
                    ContentUnavailableView {
                        Label(query.isEmpty ? "No kilns with this status" : "No kilns match '\(query)'",
                              systemImage: "magnifyingglass")
                    } description: {
                        Text(query.isEmpty ? "Choose another status or district." : "Check the kiln or rule ID, or clear the status filter.")
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Kiln or rule ID")
            .navigationTitle("Kilns")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { DataSourceLabel(text: model.dataSourceLabel) }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("District", selection: $district) {
                            ForEach(districts, id: \.self) { Text($0) }
                        }
                    } label: {
                        Label("District: \(district)", systemImage: "mappin.and.ellipse")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Status", selection: $status) {
                            Text("All statuses").tag(KilnStatus?.none)
                            ForEach(KilnStatus.knownCases, id: \.self) { s in
                                Label(s.label, systemImage: s.symbol).tag(Optional(s))
                            }
                        }
                    } label: {
                        Label("Status filter", systemImage: status == nil
                              ? "line.3.horizontal.decrease" : "line.3.horizontal.decrease.circle.fill")
                    }
                }
            }
            .navigationDestination(for: String.self) { id in
                KilnView(id: id)
                    .navigationTransition(.zoom(sourceID: id, in: zoom))
            }
        }
    }

    private var registryLoaded: Bool { if case .loaded = model.registryState { return true }; return false }
}

private struct KilnRow: View {
    @Environment(AppModel.self) private var model
    let kiln: Kiln
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize || model.usesPublicRegistry
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.xs))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Space.s))
        layout {
            VStack(alignment: .leading, spacing: Space.xxs) {
                KilnIDLabel(kiln: kiln, predictionOnly: model.usesPublicRegistry, abbreviatesID: model.usesPublicRegistry)
                if let top = kiln.topViolation {
                    Text("\(Text(top.ruleId).monospaced()) · \(top.compactLine(for: kiln))")
                        .font(.subheadline)
                        .foregroundStyle(.ink)
                    if model.usesPublicRegistry {
                        Text("Siting flag · needs inspection").font(.footnote).foregroundStyle(.flagged)
                        ThresholdWarning(verification: kiln.ruleChecks?.first { $0.ruleId == top.ruleId }?.verification)
                    }
                } else {
                    Text("No rule flags measured").font(.subheadline).foregroundStyle(.inkSecondary)
                    if let note = kiln.assessmentNote { Text(note).font(.footnote).foregroundStyle(.inkSecondary) }
                }
            }
            if !typeSize.isAccessibilitySize && !model.usesPublicRegistry { Spacer(minLength: Space.xs) }
            VStack(alignment: typeSize.isAccessibilitySize || model.usesPublicRegistry ? .leading : .trailing, spacing: Space.xxs) {
                StatusBadge(status: model.status(for: kiln), detailed: model.usesPublicRegistry)
                Text(kiln.exposure.map { model.usesPublicRegistry ? "\($0.people.grouped) modelled residents within 800 m" : "\($0.people.grouped) people · sample" } ?? "Population exposure not assessed")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.inkSecondary)
            }
        }
        .padding(.vertical, Space.xxs)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("kiln-row-\(kiln.kilnId)")
    }
}

#Preview {
    KilnsView().environment(AppModel(useFixtures: true))
}
