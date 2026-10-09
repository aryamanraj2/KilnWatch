import KilnWatchCore
import SwiftUI

extension KilnStatus {
    /// Short word used in badges and lists.
    var label: String {
        switch self {
        case .flagged: "Flagged"
        case .confirmed: "Confirmed violation"
        case .compliant: "Compliant"
        case .notAKiln: "Not a kiln"
        case .closed: "Closed"
        case .unknown(let raw): "Status: \(raw.replacingOccurrences(of: "_", with: " "))"
        }
    }

    /// Long form for the kiln header. Before a verdict the line is always this exact copy.
    var detail: String {
        switch self {
        case .flagged: "Flagged by satellite · pending inspection"
        case .closed: "Closed or not firing"
        default: label
        }
    }

    var symbol: String {
        switch self {
        case .flagged: "flag.fill"
        case .confirmed: "exclamationmark.octagon.fill"
        case .compliant: "checkmark.seal.fill"
        case .notAKiln: "square.slash"
        case .closed: "pause.circle.fill"
        case .unknown: "questionmark.circle"
        }
    }

    var color: Color {
        switch self {
        case .flagged: .flagged
        case .confirmed: .confirmed
        case .compliant: .compliant
        case .notAKiln: .notKiln
        case .closed: .closed
        case .unknown: .inkSecondary
        }
    }
}

/// Status is never color alone: symbol, word and tinted capsule.
struct StatusBadge: View {
    let status: KilnStatus
    var detailed = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.xxs) {
            Image(systemName: status.symbol)
                .imageScale(.small)
            Text(detailed ? status.detail : status.label)
        }
        .font(.footnote.weight(.semibold))
        .foregroundStyle(status.color)
        .padding(.horizontal, Space.s)
        .padding(.vertical, Space.xxs)
        .background(status.color.opacity(0.12), in: .capsule)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Status: \(status.detail)")
    }
}

#Preview("All statuses") {
    VStack(alignment: .leading, spacing: Space.s) {
        ForEach(KilnStatus.knownCases, id: \.self) { StatusBadge(status: $0) }
        StatusBadge(status: .flagged, detailed: true)
    }
    .padding(Space.margin)
    .background(.canvas)
}
