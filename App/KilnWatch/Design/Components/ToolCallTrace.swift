import SwiftUI

/// One agent tool call and its result, for example `search_kilns · 214 flagged`.
struct ToolStep: Hashable, Identifiable, Sendable {
    let tool: String
    let value: Int
    let unit: String
    var id: String { tool }
}

/// How an agent answer was built. Rows land one after another; collapses to "N steps" when the answer is done.
struct ToolCallTrace: View {
    let steps: [ToolStep]
    /// Steps whose result has arrived.
    let completed: Int
    let isDone: Bool

    @State private var expanded = true
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: Space.xs) {
                ForEach(Array(steps.prefix(min(completed + 1, steps.count)).enumerated()), id: \.element.id) { index, step in
                    TraceRow(step: step, finished: index < completed)
                        .transition(.opacity)
                }
            }
            .padding(.top, Space.xs)
        } label: {
            Text(isDone ? "\(steps.count) steps" : "Working · \(steps[min(completed, steps.count - 1)].tool)")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.inkSecondary)
                .contentTransition(.opacity)
        }
        .tint(.inkSecondary)
        .onChange(of: isDone) { _, done in
            guard done else { return }
            withAnimation(Motion.layout.animation(reduceMotion: reduceMotion)) { expanded = false }
        }
    }
}

private struct TraceRow: View {
    let step: ToolStep
    let finished: Bool

    var body: some View {
        HStack(spacing: Space.xs) {
            ZStack {
                if finished {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(.inkSecondary)
                        .transition(.symbolEffect(.drawOn))
                } else {
                    ProgressView().controlSize(.mini)
                }
            }
            .frame(width: 20)
            Text(step.tool)
                .font(.footnote.monospaced())
                .foregroundStyle(.ink)
            Spacer(minLength: Space.xs)
            Text("\(finished ? step.value : 0) \(step.unit)")
                .font(.footnote.monospacedDigit())
                .foregroundStyle(.inkSecondary)
                .contentTransition(.numericText(value: Double(finished ? step.value : 0)))
                .opacity(finished ? 1 : 0)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(finished ? "\(step.tool), \(step.value) \(step.unit)" : "\(step.tool), running")
    }
}

extension ToolStep {
    static let planDay: [ToolStep] = [
        .init(tool: "search_kilns", value: 214, unit: "flagged"),
        .init(tool: "get_evidence", value: 9, unit: "kilns"),
        .init(tool: "plan_route", value: 9, unit: "stops"),
        .init(tool: "inspection_sheet", value: 9, unit: "sheets"),
    ]
}

#Preview {
    @Previewable @State var completed = 0
    VStack(alignment: .leading, spacing: Space.xl) {
        ToolCallTrace(steps: ToolStep.planDay, completed: completed, isDone: completed == 4)
        Button("Next step") { withAnimation { completed = min(completed + 1, 4) } }
        ToolCallTrace(steps: ToolStep.planDay, completed: 4, isDone: true)
    }
    .padding(Space.margin)
    .background(.canvas)
}
