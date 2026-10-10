import KilnWatchCore
import SwiftUI

/// A reference may carry this kiln's exact check/flag, or catalog text only.
struct RuleReference: Identifiable {
    let rule: Rule
    var check: RuleCheck?
    var flag: Violation?
    var kilnId: String?
    var id: String { rule.id }

    static func catalog(_ id: String) -> Self { .init(rule: .named(id)) }
    var verification: ThresholdVerification? {
        if let check { return check.verification }
        // Only bundled reference warnings. Never infer verification for a live flag without a check.
        if flag != nil { return nil }
        guard Fixtures.rules.contains(where: { $0.id == rule.id }) else { return nil }
        return ["UP-SCH-1K", "UP-NH-300", "UP-RAIL-200", "C-TECH-10K"].contains(rule.id)
            ? .unverifiedCompilation : .secondarySources
    }
}

struct ThresholdWarning: View {
    let verification: ThresholdVerification?
    var body: some View {
        Label(verification?.label ?? "Threshold verification unavailable", systemImage: "exclamationmark.triangle")
            .font(.footnote)
            .foregroundStyle(.inkSecondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}

struct RuleCheckRow: View {
    let check: RuleCheck
    let kilnId: String
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Space.xs) { header }
                VStack(alignment: .leading, spacing: Space.xxs) { header }
            }
            Label(check.status.label, systemImage: check.status == .withinThreshold ? "flag.fill" : "info.circle")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(check.status == .withinThreshold ? Color.flagged : Color.inkSecondary)
            Text(check.measurementLine).font(.subheadline.monospacedDigit()).foregroundStyle(.ink)
            ThresholdWarning(verification: check.verification)
            Text(check.source.isEmpty ? "Source unavailable" : check.source)
                .font(.footnote).foregroundStyle(.inkSecondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .contain)
        .accessibilityAction(named: "Show rule \(check.ruleId)") { showSource() }
    }
    @ViewBuilder private var header: some View {
        CitationChip(id: check.ruleId, action: showSource)
        Text(check.check).font(.subheadline.weight(.semibold)).foregroundStyle(.ink)
    }
    private func showSource() {
        model.shownRule = RuleReference(rule: .named(check.ruleId), check: check, kilnId: kilnId)
    }
}
