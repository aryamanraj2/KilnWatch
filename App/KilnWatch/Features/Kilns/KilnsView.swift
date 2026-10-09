import SwiftUI

/// The searchable registry.
struct KilnsView: View {
    @Environment(AppModel.self) private var model
    @Namespace private var zoom
    @State private var query = UserDefaults.standard.string(forKey: "query") ?? ""
    @State private var status: KilnStatus?
    @State private var district = "Hapur"

    private var results: [Kiln] {
        model.allKilns.filter { kiln in
            kiln.district == district
                && (status == nil || kiln.status == status)
                && (query.isEmpty
                    || kiln.kilnID.localizedStandardContains(query)
                    || kiln.violations.contains { $0.ruleID.localizedStandardContains(query) })
        }
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.kilnsPath) {
            List {
                Section {
                    ForEach(results) { kiln in
                        NavigationLink(value: kiln.kilnID) { KilnRow(kiln: kiln) }
                            .matchedTransitionSource(id: kiln.kilnID, in: zoom)
                            .listRowBackground(Color.surface)
                    }
                } header: {
                    if !results.isEmpty {
                        Text("\(district) · \(results.count) kilns").eyebrow()
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(.canvas)
            .redacted(reason: model.isLoading ? .placeholder : [])
            .overlay {
                if results.isEmpty {
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
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("District", selection: $district) {
                            ForEach(Mock.districts, id: \.self) { Text($0) }
                        }
                    } label: {
                        Label("District: \(district)", systemImage: "mappin.and.ellipse")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Status", selection: $status) {
                            Text("All statuses").tag(KilnStatus?.none)
                            ForEach(KilnStatus.allCases, id: \.self) { s in
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
}

private struct KilnRow: View {
    let kiln: Kiln
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.xs))
            : AnyLayout(HStackLayout(alignment: .top, spacing: Space.s))
        layout {
            VStack(alignment: .leading, spacing: Space.xxs) {
                KilnIDLabel(kiln: kiln)
                if let top = kiln.topViolation {
                    Text("\(Text(top.ruleID).monospaced()) · \(top.compactLine(for: kiln))")
                        .font(.subheadline)
                        .foregroundStyle(.ink)
                }
            }
            if !typeSize.isAccessibilitySize { Spacer(minLength: Space.xs) }
            VStack(alignment: typeSize.isAccessibilitySize ? .leading : .trailing, spacing: Space.xxs) {
                StatusBadge(status: kiln.status)
                Text("\(kiln.exposure.peopleWithin800m.grouped) people")
                    .font(.footnote.monospacedDigit())
                    .foregroundStyle(.inkSecondary)
            }
        }
        .padding(.vertical, Space.xxs)
        .accessibilityElement(children: .combine)
    }
}

#Preview {
    KilnsView().environment(AppModel())
}
