import SwiftUI

/// A conversation with the planner agent. Phase 0 plays scripted exchanges from the concept (p.13).
struct AskView: View {
    @Environment(AppModel.self) private var model
    @State private var exchanges: [Exchange] = []
    @FocusState private var composerFocused: Bool

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.askPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xxl) {
                    if exchanges.isEmpty {
                        suggestions
                    }
                    ForEach($exchanges) { $exchange in
                        ExchangeView(exchange: $exchange)
                    }
                }
                .padding(.horizontal, Space.margin)
                .padding(.vertical, Space.m)
            }
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
            .scrollDismissesKeyboard(.interactively)
            .background(.canvas)
            .navigationTitle("Ask KilnWatch")
            .safeAreaBar(edge: .bottom) { composer }
            .navigationDestination(for: String.self) { KilnView(id: $0) }
            .onAppear {
                if UserDefaults.standard.bool(forKey: "askPlay"), exchanges.isEmpty { send(AskScript.planDay.question) }
            }
        }
    }

    // MARK: Empty state

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text("The planner searches the registry, orders stops and writes inspection sheets. Every answer cites the kilns and rules it used.")
                .font(.body)
                .foregroundStyle(.inkSecondary)
            Text("Try").eyebrow()
            VStack(spacing: Space.xs) {
                ForEach(AskScript.all, id: \.question) { script in
                    Button { send(script.question) } label: {
                        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                            Text(script.question)
                                .font(.body)
                                .foregroundStyle(.ink)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: Space.xs)
                            Image(systemName: "arrow.up.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.inkSecondary)
                                .accessibilityHidden(true)
                        }
                        .frame(minHeight: 44)
                        .card()
                    }
                    .buttonStyle(.plain)
                    .disabled(model.isOffline)
                }
            }
        }
    }

    // MARK: Composer

    private var composer: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: Space.xs) {
            if model.isOffline {
                QuietBanner(text: "Offline · Ask needs a connection", systemImage: "wifi.slash")
            }
            HStack(alignment: .bottom, spacing: Space.xs) {
                TextField("Ask about any kiln…", text: $model.askDraft, axis: .vertical)
                    .lineLimit(1...4)
                    .focused($composerFocused)
                    .submitLabel(.send)
                    .onSubmit { send(model.askDraft) }
                    .padding(.vertical, Space.s)
                Button { send(model.askDraft) } label: {
                    Image(systemName: "arrow.up")
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.canvas)
                        .frame(width: 36, height: 36)
                        .background(.ink, in: .circle)
                        .frame(width: 44, height: 44)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Send")
                .disabled(model.askDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.leading, Space.m)
            .padding(.trailing, Space.xxs)
            .glassEffect(.regular, in: .rect(cornerRadius: 26, style: .continuous))
            .disabled(model.isOffline)
            Text("Answers cite registry records. Agents never record verdicts.")
                .font(.footnote)
                .foregroundStyle(.inkSecondary)
                .padding(.horizontal, Space.xs)
        }
        .padding(.horizontal, Space.margin)
        .padding(.bottom, Space.xs)
    }

    private func send(_ text: String) {
        let question = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        exchanges.append(Exchange(question: question, script: AskScript.matching(question)))
        model.askDraft = ""
        composerFocused = false
    }
}

// MARK: - Exchange

struct Exchange: Identifiable {
    let id = UUID()
    let question: String
    let script: AskScript
    var completedSteps = 0
    var revealedTokens = 0
    var isDone = false
}

private struct ExchangeView: View {
    @Binding var exchange: Exchange
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(exchange.question)
                .font(.body)
                .foregroundStyle(.ink)
                .padding(.horizontal, Space.m)
                .padding(.vertical, Space.s)
                .background(.surface2, in: .rect(cornerRadius: Radius.card, style: .continuous))
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.leading, Space.xxxl)
                .accessibilityLabel("You asked: \(exchange.question)")

            ToolCallTrace(steps: exchange.script.steps, completed: exchange.completedSteps, isDone: exchange.isDone)

            if exchange.revealedTokens > 0 {
                AnswerText(tokens: Array(exchange.script.tokens.prefix(exchange.revealedTokens)),
                           fullText: exchange.script.plainAnswer)
            }
        }
        .task { await play() }
    }

    /// Steps land one after another, then the answer streams word by word.
    private func play() async {
        guard !exchange.isDone, exchange.completedSteps == 0 else { return }
        for _ in exchange.script.steps {
            try? await Task.sleep(for: .milliseconds(550))
            withAnimation(Motion.select.animation(reduceMotion: reduceMotion)) { exchange.completedSteps += 1 }
        }
        try? await Task.sleep(for: .milliseconds(250))
        for _ in exchange.script.tokens {
            try? await Task.sleep(for: .milliseconds(45))
            withAnimation(.easeOut(duration: 0.2)) { exchange.revealedTokens += 1 }
        }
        exchange.isDone = true
    }
}

/// Answer prose with inline citation chips, wrapped word by word.
private struct AnswerText: View {
    let tokens: [AskScript.Token]
    let fullText: String

    var body: some View {
        FlowLayout(spacing: 4, lineSpacing: Space.xs) {
            ForEach(Array(tokens.enumerated()), id: \.offset) { _, token in
                switch token {
                case .word(let word):
                    Text(word).font(.body).foregroundStyle(.ink)
                case .cite(let id, let trailing):
                    HStack(spacing: 0) {
                        CitationChip(id: id)
                        if !trailing.isEmpty { Text(trailing).font(.body).foregroundStyle(.ink) }
                    }
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(fullText)
        .accessibilityActions {
            ForEach(Array(Set(tokens.compactMap(\.citation))).sorted(), id: \.self) { id in
                Button(id.hasPrefix("KW-") ? "Open \(id)" : "Show rule \(id)") { openURL(CitationChip.url(for: id)) }
            }
        }
    }

    @Environment(\.openURL) private var openURL
}

/// Left-to-right wrapping layout that aligns each line on its first text baseline.
private struct FlowLayout: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        return arrange(subviews, width: width).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for (index, origin) in arrange(subviews, width: bounds.width).origins.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y), proposal: .unspecified)
        }
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> (origins: [CGPoint], size: CGSize) {
        var origins: [CGPoint] = []
        var lines: [[Int]] = [[]]
        var x: CGFloat = 0
        for (i, view) in subviews.enumerated() {
            let w = view.sizeThatFits(.unspecified).width
            if x > 0, x + w > width { lines.append([]); x = 0 }
            lines[lines.count - 1].append(i)
            x += w + spacing
        }
        var y: CGFloat = 0
        var maxX: CGFloat = 0
        origins = Array(repeating: .zero, count: subviews.count)
        for line in lines where !line.isEmpty {
            let dims = line.map { subviews[$0].dimensions(in: .unspecified) }
            let ascent = dims.map { $0[.firstTextBaseline] }.max() ?? 0
            let descent = dims.map { $0.height - $0[.firstTextBaseline] }.max() ?? 0
            var lineX: CGFloat = 0
            for (i, d) in zip(line, dims) {
                origins[i] = CGPoint(x: lineX, y: y + ascent - d[.firstTextBaseline])
                lineX += d.width + spacing
            }
            maxX = max(maxX, lineX - spacing)
            y += ascent + descent + lineSpacing
        }
        return (origins, CGSize(width: min(maxX, width), height: max(0, y - lineSpacing)))
    }
}

// MARK: - Scripts

struct AskScript {
    enum Token: Hashable {
        case word(String)
        case cite(String, trailing: String)

        var citation: String? {
            if case .cite(let id, _) = self { id } else { nil }
        }
    }

    let question: String
    let steps: [ToolStep]
    /// Prose with citations in brackets: "[KW-0412]".
    let answer: String

    var tokens: [Token] {
        answer.split(separator: " ").map { raw in
            let word = String(raw)
            guard word.hasPrefix("["), let close = word.firstIndex(of: "]") else { return .word(word) }
            let id = String(word[word.index(after: word.startIndex)..<close])
            return .cite(id, trailing: String(word[word.index(after: close)...]))
        }
    }

    var plainAnswer: String { answer.replacingOccurrences(of: "[", with: "").replacingOccurrences(of: "]", with: "") }

    static let planDay = AskScript(
        question: "Plan tomorrow in Hapur. Six hours. Schools first.",
        steps: ToolStep.planDay,
        answer: "Nine stops, ranked by people exposed. Four are within 1 km of a school under [UP-SCH-1K]: [KW-0412], [KW-0388], [KW-0433] and [KW-0467]. The day starts at [KW-0412], 410 m from homes against the 800 m in [C-HAB-800]. Sheets are ready for each stop. Leave at 9:00 to finish by 14:40."
    )

    static let nearHomes = AskScript(
        question: "Which kilns near Pilkhuwa are within 800 m of homes?",
        steps: [.init(tool: "search_kilns", value: 38, unit: "flagged"), .init(tool: "get_evidence", value: 2, unit: "kilns")],
        answer: "Two kilns near Pilkhuwa are within 800 m of homes under [C-HAB-800]: [KW-0412] at 410 m and [KW-0388] at 520 m. Both are flagged by satellite and pending inspection. Both are on tomorrow's route as stops 1 and 2."
    )

    static let sheet = AskScript(
        question: "Prepare the inspection sheet for KW-0412.",
        steps: [.init(tool: "get_evidence", value: 1, unit: "kiln"), .init(tool: "inspection_sheet", value: 1, unit: "sheet")],
        answer: "The sheet for [KW-0412] is ready. Check the chimney type, since [C-TECH-10K] requires zigzag within 10 km of Delhi. Note the fuel on site. Confirm the nearest home, measured at 410 m against [C-HAB-800]. 6,240 people live within 800 m."
    )

    static let all = [planDay, nearHomes, sheet]

    /// Phase 0 has no agent; free text plays the planner exchange.
    static func matching(_ question: String) -> AskScript {
        all.first { $0.question == question } ?? planDay
    }
}

#Preview {
    AskView().environment(AppModel())
}
