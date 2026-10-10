import SwiftUI

/// Shared honest network state for the list, map and on-demand detail.
struct RegistryStateView: View {
    let state: RegistryState
    let district: String
    var retrying = false
    let retry: () async -> Void
    @State private var retryID = 0

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            if case .loading = state { ProgressView().accessibilityLabel("Loading satellite records") }
            Text(state.message)
                .font(.title2.weight(.semibold))
                .foregroundStyle(.ink)
                .accessibilityAddTraits(.isHeader)
            Text(description)
                .font(.body)
                .foregroundStyle(.inkSecondary)
            Button("Retry", systemImage: "arrow.clockwise") { retryID += 1 }
                .buttonStyle(.secondary)
                .disabled(retrying)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Space.margin)
        .task(id: retryID) { if retryID > 0 { await retry() } }
    }

    private var description: String {
        switch state {
        case .empty: "No flagged kilns in \(district) in the scanned imagery"
        case .offline: "Connect to the internet, then retry. Satellite records aren't saved on this device."
        case .busy(let retrying): retrying ? "We'll try once more in a moment." : "The service is still busy. Please retry shortly."
        case .unavailable: "Please retry in a moment."
        case .notFound: "This public record is no longer available."
        case .failure: "Please retry. If this continues, try again later."
        case .interrupted: "Retry to load the satellite record."
        case .loading: "Fetching the public registry for \(district)."
        case .loaded: ""
        }
    }
}

struct DataSourceLabel: View {
    let text: String
    var body: some View {
        HStack(spacing: Space.xxs) {
            Image(systemName: text == "Live data" ? "antenna.radiowaves.left.and.right" : "square.stack")
                .accessibilityHidden(true)
            Text(text)
        }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.inkSecondary)
            .padding(.horizontal, Space.s)
            .padding(.vertical, Space.xxs)
            .background(.surface2, in: .capsule)
            .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
            .fixedSize()
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(text)
    }
}
