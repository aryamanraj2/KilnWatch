import KilnWatchCore
import SwiftUI

/// The hero of the app: a measured distance against a legal threshold.
/// Track = threshold (or the measurement, if larger), fill = measured, tick = threshold.
struct RuleDistanceBar: View {
    let violation: Violation
    let kiln: Kiln
    var check: RuleCheck?
    var color: Color = .flagged

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(AppModel.self) private var model

    private var rule: Rule { Rule.named(violation.ruleId) }

    var body: some View {
        content
            .onScrollVisibilityChange(threshold: 0.6) { visible in
                guard visible, !appeared else { return }
                withAnimation(Motion.layout.animation(reduceMotion: reduceMotion)) { appeared = true }
            }
            .accessibilityRepresentation {
                Text(accessibilityText)
                    .accessibilityAction(named: "Show rule \(violation.ruleId)") { showSource() }
            }
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Space.xs) { header }
                VStack(alignment: .leading, spacing: Space.xxs) { header }
            }
            Label("Siting flag · needs inspection", systemImage: "flag.fill")
                .font(.footnote).foregroundStyle(.flagged)
            if RuleCheck.canDrawBar(measured: violation.measuredDistanceM, threshold: violation.thresholdM),
               let measured = violation.measuredDistanceM, let threshold = violation.thresholdM {
                bar(measured: measured, threshold: threshold)
                Text(violation.compactLine(for: kiln)).monospacedDigit()
                    .font(.subheadline)
                    .foregroundStyle(.ink)
            } else {
                Text(legacyTechnology ? technologyLine : violation.compactLine(for: nil))
                    .font(.subheadline)
                    .foregroundStyle(.ink)
            }
            ThresholdWarning(verification: check?.verification)
            Text(violation.source.isEmpty ? "Source unavailable" : violation.source)
                .font(.footnote).foregroundStyle(.inkSecondary)
            if let check, check.status != .withinThreshold {
                Text("Supplied check: \(check.status.label). Flag and check differ; inspect on site.")
                    .font(.footnote).foregroundStyle(.inkSecondary)
            }
        }
    }

    private var legacyTechnology: Bool {
        violation.ruleId == "C-TECH-10K" && model.usesIllustrativeEvidence(for: kiln) && check == nil
    }
    private func showSource() {
        model.shownRule = RuleReference(rule: rule, check: check, flag: violation, kilnId: kiln.kilnId)
    }

    @ViewBuilder private var header: some View {
        CitationChip(id: violation.ruleId, action: showSource)
        Text(check?.check ?? rule.name)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.ink)
    }

    private func bar(measured: Double, threshold: Double) -> some View {
        let scale = max(threshold, measured)
        let fraction = measured / scale
        return ZStack {
            Capsule().fill(.surface2)
            BarFill(fraction: reduceMotion || appeared ? fraction : 0)
                .fill(color)
            ThresholdTick(position: threshold / scale)
                .fill(.ink)
                .padding(.vertical, -Space.xxs)
        }
        .frame(height: 8)
        .padding(.vertical, Space.xxs)
    }

    private var technologyLine: String {
        let found = kiln.typeIsCertain ? "\(kiln.type.rawValue) found" : "Likely \(kiln.type.rawValue) found"
        let tail = kiln.typeIsCertain ? "" : " · confirm on site"
        return "\(found) · zigzag required within 10 km of Delhi\(tail)"
    }

    private var accessibilityText: String {
        "\(check?.check ?? rule.name). Siting flag, needs inspection. \(legacyTechnology ? technologyLine : violation.compactLine(for: nil)). Rule \(violation.ruleId). \(check?.verification?.label ?? "Threshold verification unavailable"). \(violation.source).\(check.map { $0.status != .withinThreshold ? " Supplied check: \($0.status.label). Flag and check differ; inspect on site." : "" } ?? "")"
    }
}

/// Capsule fill of `fraction` × width, animatable from 0.
@Animatable
private struct BarFill: Shape {
    var fraction: Double

    func path(in rect: CGRect) -> Path {
        let width = rect.width * fraction
        guard width > 0 else { return Path() }
        return Capsule().path(in: CGRect(x: 0, y: 0, width: max(width, rect.height), height: rect.height))
    }
}

/// 2 pt threshold tick, slightly taller than the track.
private struct ThresholdTick: Shape {
    let position: Double

    func path(in rect: CGRect) -> Path {
        let x = min(rect.width * position, rect.width - 1)
        return Capsule().path(in: CGRect(x: x - 1, y: 0, width: 2, height: rect.height))
    }
}

#Preview {
    let kiln = Mock.route[0]
    ScrollView {
        VStack(alignment: .leading, spacing: Space.xl) {
            ForEach(kiln.violations, id: \.ruleId) { RuleDistanceBar(violation: $0, kiln: kiln) }
            RuleDistanceBar(violation: Mock.route[3].violations[1], kiln: Mock.route[3])
            RuleDistanceBar(violation: Mock.registry[10].violations[0], kiln: Mock.registry[10], color: .compliant)
        }
        .card()
        .padding(Space.margin)
    }
    .background(.canvas)
}

extension Violation {
    /// One plain line stating the measurement against the rule: "410 m from homes · rule requires 800 m".
    func factLine(for kiln: Kiln) -> String {
        let rule = Rule.named(ruleId)
        guard let m = RuleCheck.metres(measuredDistanceM), let t = RuleCheck.metres(thresholdM) else { return compactLine(for: nil) }
        return "\(m) from \(rule.feature) · rule requires \(t)"
    }

    /// Short form for list rows: "410 m · requires 800 m".
    func compactLine(for kiln: Kiln?) -> String {
        let measurement = RuleCheck.metres(measuredDistanceM) ?? "Distance unavailable"
        let threshold = RuleCheck.metres(thresholdM).map { "requires \($0)" } ?? "threshold unavailable"
        return "\(measurement) · \(threshold)"
    }
}
