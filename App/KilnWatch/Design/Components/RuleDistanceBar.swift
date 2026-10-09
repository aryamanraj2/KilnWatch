import KilnWatchCore
import SwiftUI

/// The hero of the app: a measured distance against a legal threshold.
/// Track = threshold (or the measurement, if larger), fill = measured, tick = threshold.
struct RuleDistanceBar: View {
    let violation: Violation
    let kiln: Kiln
    var color: Color = .flagged

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var rule: Rule { Rule.named(violation.ruleId) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Space.xs) { header }
                VStack(alignment: .leading, spacing: Space.xxs) { header }
            }
            if let measured = violation.measuredDistanceM, let threshold = violation.thresholdM {
                bar(measured: measured, threshold: threshold)
                let shown = appeared ? measured : 0
                Text("\(Text("\(Int(shown).grouped)\u{00A0}m").monospaced()) · requires \(Text("\(Int(threshold).grouped)\u{00A0}m").monospaced())")
                    .contentTransition(.numericText(value: shown))
                    .font(.subheadline)
                    .foregroundStyle(.ink)
            } else {
                Text(technologyLine)
                    .font(.subheadline)
                    .foregroundStyle(.ink)
            }
        }
        .onScrollVisibilityChange(threshold: 0.6) { visible in
            guard visible, !appeared else { return }
            withAnimation(Motion.layout.animation(reduceMotion: reduceMotion)) { appeared = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityAction(named: "Show rule \(violation.ruleId)") {
            openURL(CitationChip.url(for: violation.ruleId))
        }
    }

    @Environment(\.openURL) private var openURL

    @ViewBuilder private var header: some View {
        CitationChip(id: violation.ruleId)
        Text(rule.name)
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
                .opacity(reduceMotion && !appeared ? 0 : 1)
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
        guard let m = violation.measuredDistanceM, let t = violation.thresholdM else {
            return "\(rule.name). \(technologyLine). Rule \(violation.ruleId)."
        }
        return "\(rule.name), \(Int(m).grouped) metres. Rule \(violation.ruleId) requires \(Int(t).grouped) metres."
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
        guard let m = measuredDistanceM, let t = thresholdM else {
            let type = kiln.typeIsCertain ? kiln.type.rawValue : "Likely \(kiln.type.rawValue)"
            return "\(type) within 10 km of Delhi · rule requires zigzag\(kiln.typeIsCertain ? "" : " · confirm on site")"
        }
        return "\(Int(m).grouped)\u{00A0}m from \(rule.feature) · rule requires \(Int(t).grouped)\u{00A0}m"
    }

    /// Short form for list rows: "410 m · requires 800 m".
    func compactLine(for kiln: Kiln) -> String {
        guard let m = measuredDistanceM, let t = thresholdM else {
            return "\(kiln.typeIsCertain ? "" : "likely ")\(kiln.type.rawValue) · zigzag required"
        }
        return "\(Int(m).grouped)\u{00A0}m · requires \(Int(t).grouped)\u{00A0}m"
    }
}
