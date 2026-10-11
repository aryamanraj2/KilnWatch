import KilnWatchCore
import MapKit
import SwiftUI

struct ReviewView: View {
    @Environment(AppModel.self) private var model
    @Namespace private var zoom
    @State private var location: ReviewItem?
    @State private var expanded: Set<String> = []

    private var loading: Bool { model.review.isLoading || model.demo == .loading }
    private var groups: [(ReviewGroup, [ReviewItem])] {
        guard let queue = model.review.queue else { return [] }
        let known = ReviewGroup.ordered.compactMap { group -> (ReviewGroup, [ReviewItem])? in
            let items = queue.items.filter { $0.displayGroup == group }
            if group == .possibleZigzagConversion && queue.counts[group] == 0 && items.isEmpty { return nil }
            return (group, items)
        }
        let other = queue.items.filter { !ReviewGroup.ordered.contains($0.displayGroup) }
        return known + (other.isEmpty ? [] : [(.unknown("future"), other)])
    }

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.reviewPath) {
            List {
                Section {
                    ReviewHeader(queue: loading ? nil : model.review.queue)
                    if model.review.offline {
                        Label("Offline · showing saved review list", systemImage: "wifi.slash")
                            .font(.footnote).foregroundStyle(.inkSecondary)
                    }
                    if let message = model.review.message {
                        Text(message).font(.body).foregroundStyle(.inkSecondary)
                        Button("Retry", systemImage: "arrow.clockwise") { Task { await model.loadReview(force: true) } }
                            .frame(minHeight: 44).disabled(loading)
                    }
                    if let warning = model.review.cacheWarning {
                        Text(warning).font(.footnote).foregroundStyle(.inkSecondary)
                    }
                }.listRowBackground(Color.canvas)
                if loading {
                    Section {
                        ForEach(0..<3, id: \.self) { _ in
                            VStack(alignment: .leading, spacing: Space.s) {
                                Text("Satellite review item").font(.headline)
                                Text("Detector score · pending review").font(.subheadline)
                                Text("A difference between the two satellite scenes is waiting for review.")
                            }.redacted(reason: .placeholder).accessibilityHidden(true)
                        }
                    } header: { Text("Loading review list").eyebrow() }
                } else if model.review.queue?.items.isEmpty == true {
                    Text("No changes queued for review").foregroundStyle(.inkSecondary)
                } else {
                    ForEach(groups, id: \.0) { group, items in
                        Section {
                            ForEach(items) { item in
                                ReviewRow(item: item, expanded: expanded.contains(item.id),
                                          open: { open(item) }, toggle: { toggle(item) })
                                    .matchedTransitionSource(id: item.kilnId ?? item.id, in: zoom)
                                    .listRowBackground(Color.surface)
                            }
                        } header: {
                            Text("\(group.label) · \(sectionCount(group, items: items))")
                                .font(.footnote.weight(.semibold)).foregroundStyle(.inkSecondary)
                                .textCase(nil).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                Section {
                    Text("The change-triage agent queues differences for review. Only a reviewer's approval changes the registry; approval needs sign-in and is not available yet.")
                        .font(.footnote).foregroundStyle(.inkSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }.listRowBackground(Color.canvas)
            }
            .scrollContentBackground(.hidden).background(.canvas)
            .scrollEdgeEffectStyle(.hard, for: .top)
            .navigationTitle("Review")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    DataSourceLabel(text: model.demo == .live ? model.dataSourceLabel : "Sample data")
                }
            }
            .task { await model.loadReview() }
            .refreshable { await model.loadReview(force: true) }
            .navigationDestination(for: String.self) { id in
                KilnView(id: id).navigationTransition(.zoom(sourceID: id, in: zoom))
            }
            .navigationDestination(item: $location) { item in
                ReviewLocationView(item: item, queue: model.review.queue)
            }
        }
    }
    private func sectionCount(_ group: ReviewGroup, items: [ReviewItem]) -> Int {
        if case .unknown = group { return items.count }
        return model.review.queue?.counts[group] ?? items.count
    }
    private func open(_ item: ReviewItem) {
        if let id = item.kilnId { model.reviewPath.append(id) }
        else { location = item }
    }
    private func toggle(_ item: ReviewItem) {
        if expanded.contains(item.id) { expanded.remove(item.id) } else { expanded.insert(item.id) }
    }
}

private struct ReviewHeader: View {
    let queue: ReviewQueue?
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text("Changes since Dec 2023 · pending review").font(.subheadline).foregroundStyle(.ink)
            if let baseline = queue?.baseline, let current = queue?.current {
                Text("\(reviewDate(baseline.date)) → \(reviewDate(current.date))")
                    .font(.footnote.monospaced()).foregroundStyle(.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let queue {
                Text("\(queue.counts.newCandidate) not detected in 2023 · \(queue.counts.noLongerDetected) no longer detected · \(queue.counts.possibleZigzagConversion) possible zigzag conversions · \(queue.counts.lowConfidence) low detector scores")
                    .font(.footnote.monospacedDigit()).foregroundStyle(.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if queue.truncated { Text("Showing the first 500").font(.footnote).foregroundStyle(.inkSecondary) }
            }
        }.padding(.vertical, Space.xxs)
    }
}

private struct ReviewRow: View {
    let item: ReviewItem
    let expanded: Bool
    let open: () -> Void
    let toggle: () -> Void
    @Environment(\.dynamicTypeSize) private var size
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            VStack(alignment: .leading, spacing: Space.xs) {
                    Text(item.kilnId ?? "Not in registry")
                        .font(.subheadline.weight(.semibold).monospaced()).foregroundStyle(.ink)
                        .typesettingLanguage(.explicit(.init(identifier: "zxx")))
                        .fixedSize(horizontal: false, vertical: true)
                    let layout = size.isAccessibilitySize
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.xs))
                        : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: Space.s))
                    layout {
                        VStack(alignment: .leading, spacing: Space.xxs) {
                            if let prediction = item.current {
                                Text("\(prediction.type.rawValue) · score \(reviewScore(prediction.score))")
                            }
                            if let prediction = item.baseline {
                                Text("2023: \(prediction.type.rawValue) · \(reviewScore(prediction.score))")
                            }
                        }.font(.footnote.monospacedDigit()).foregroundStyle(.inkSecondary)
                        ReviewPendingBadge(known: item.state == .pending)
                    }
            }
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            Text(item.reason).font(.subheadline).foregroundStyle(.ink)
                .lineLimit(expanded ? nil : 3).fixedSize(horizontal: false, vertical: true)
            Button(expanded ? "Less" : "More") {
                withAnimation(Motion.layout.animation(reduceMotion: reduceMotion)) { toggle() }
            }
            .font(.footnote.weight(.semibold)).foregroundStyle(.inkSecondary)
            .frame(minWidth: 44, minHeight: 44, alignment: .leading).buttonStyle(.plain)
        }
        .padding(.vertical, Space.xxs)
        .contentShape(.rect)
        .onTapGesture(perform: open)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(item.kilnId ?? "Not in registry"), \(spokenGroup), \(item.state == .pending ? "pending review" : "unrecognised change"). Reason: \(item.reason)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { open() }
        .accessibilityAction(named: Text(expanded ? "Show less reason" : "Show full reason")) { toggle() }
        .accessibilityIdentifier("review-row-\(item.id)")
    }
    private var spokenGroup: String {
        item.displayGroup == .newCandidate ? "not detected in December 2023" : item.displayGroup.label.lowercased()
    }
}

private struct ReviewPendingBadge: View {
    var known = true
    var body: some View {
        Label(known ? "Pending review" : "Unrecognised change", systemImage: known ? "clock" : "questionmark.circle")
            .font(.caption.weight(.medium)).foregroundStyle(.inkSecondary)
            .padding(.horizontal, Space.xs).padding(.vertical, Space.xxs)
            .background(.surface2, in: .capsule).fixedSize(horizontal: false, vertical: true)
    }
}

private struct ReviewLocationView: View {
    let item: ReviewItem
    let queue: ReviewQueue?
    @Environment(AppModel.self) private var model
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Space.l) {
                Text(item.displayGroup.label).font(.title2.weight(.semibold)).foregroundStyle(.ink)
                ReviewPendingBadge(known: item.state == .pending)
                if let baseline = item.baseline {
                    Text("2023: \(baseline.type.rawValue) · detector score \(reviewScore(baseline.score))")
                        .font(.body.monospacedDigit()).foregroundStyle(.ink)
                }
                DisclosureGroup("Reason") {
                    Text(item.reason).font(.body).foregroundStyle(.ink)
                }.font(.body).tint(.ink)
                VStack(alignment: .leading, spacing: Space.s) {
                    if let baseline = queue?.baseline {
                        Text("\(baseline.scene)\n\(reviewDate(baseline.date))")
                    }
                    if let current = queue?.current {
                        Text("\(current.scene)\n\(reviewDate(current.date))")
                    }
                    Text("\(item.centroid.lat.formatted(.number.precision(.fractionLength(5))))°, \(item.centroid.lon.formatted(.number.precision(.fractionLength(5))))°")
                }.font(.footnote.monospaced()).foregroundStyle(.inkSecondary)
                    .typesettingLanguage(.explicit(.init(identifier: "zxx")))
                    .fixedSize(horizontal: false, vertical: true)
                if item.centroid.coordinate.isValid {
                    Map(initialPosition: .region(MKCoordinateRegion(center: item.centroid.coordinate.clLocation, latitudinalMeters: 1600, longitudinalMeters: 1600)), interactionModes: []) {
                        Marker("2023 detection", coordinate: item.centroid.coordinate.clLocation).tint(.clay)
                    }
                    .dynamicTypeSize(...DynamicTypeSize.xxLarge)
                    .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
                    .frame(height: 240).clipShape(.rect(cornerRadius: Radius.card))
                    .accessibilityLabel("Location of the December 2023 detection")
                } else { Text("Location unavailable").foregroundStyle(.inkSecondary) }
                ReviewLocationEvidence(evidence: item.evidence)
            }.padding(Space.margin)
        }
        .background(.canvas).navigationTitle("Review location").navigationBarTitleDisplayMode(.inline)
        .safeAreaBar(edge: .bottom) {
            Button("Directions", systemImage: "arrow.triangle.turn.up.right.diamond") {
                model.maps.reviewLocation(item.centroid.coordinate)
            }.buttonStyle(.primary).padding(.horizontal, Space.margin).padding(.vertical, Space.xs)
                .disabled(!item.centroid.coordinate.isValid)
        }
    }
}

private struct ReviewLocationEvidence: View {
    let evidence: ReviewItem.Evidence?
    var body: some View {
        if evidence?.before == nil && evidence?.after == nil {
            Text("No published image for this location").font(.footnote).foregroundStyle(.inkSecondary)
        } else {
            ForEach([evidence?.before, evidence?.after].compactMap { $0 }, id: \.self) { url in
                AsyncImage(url: url) { phase in
                    if let image = phase.image { image.resizable().interpolation(.none).scaledToFit() }
                    else { Text("Published image unavailable").font(.footnote).foregroundStyle(.inkSecondary) }
                }.accessibilityLabel("Satellite evidence")
            }
        }
    }
}

private func reviewScore(_ score: Double) -> String { score.formatted(.number.precision(.fractionLength(2))) }
private func reviewDate(_ value: String) -> String {
    guard let date = try? Date.ISO8601FormatStyle().parse(value + "T00:00:00Z") else { return value }
    var format = Date.FormatStyle.dateTime.day().month(.abbreviated).year().locale(Locale(identifier: "en_GB"))
    format.timeZone = TimeZone(secondsFromGMT: 0)!
    return date.formatted(format)
}

#Preview { ReviewView().environment(AppModel(useFixtures: true)) }
