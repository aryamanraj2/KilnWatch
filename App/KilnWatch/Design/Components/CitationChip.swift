import SwiftUI

/// A kiln or rule ID cited by an agent or the rules engine. Tapping opens the kiln or the rule.
/// Routing goes through `openURL` (`kilnwatch://kiln/KW-0412`, `kilnwatch://rule/C-HAB-800`), handled at the app root.
struct CitationChip: View {
    let id: String
    @Environment(\.openURL) private var openURL

    static func url(for id: String) -> URL {
        URL(string: "kilnwatch://\(id.hasPrefix("KW-") ? "kiln" : "rule")/\(id)")!
    }

    var body: some View {
        Button { openURL(Self.url(for: id)) } label: {
            Text(id)
                .font(.footnote.monospaced().weight(.medium))
                .foregroundStyle(.clay)
                .padding(.horizontal, Space.xs)
                .padding(.vertical, Space.xxs)
                .background(.surface2, in: .capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(id)
        .accessibilityHint(id.hasPrefix("KW-") ? "Opens this kiln" : "Shows this rule")
    }
}

#Preview {
    HStack { CitationChip(id: "KW-0412"); CitationChip(id: "C-HAB-800") }
        .padding(Space.margin)
        .background(.canvas)
}
