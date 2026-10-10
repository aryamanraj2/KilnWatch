import KilnWatchCore
import SwiftUI

struct AskView: View {
    @Environment(AppModel.self) private var model
    @State private var samples: [Exchange] = []
    @FocusState private var composerFocused: Bool

    private var offline: Bool {
        model.usesPublicRegistry ? model.askConnectivity.isOffline || DemoOptions.string("askDemo") == "offline" : model.isOffline
    }
    private var sending: Bool { model.usesPublicRegistry ? model.ask.isSending : samples.contains { !$0.isDone } }
    private var canSend: Bool { !offline && !sending && model.ask.validation == nil && (!model.usesPublicRegistry || model.ask.canSubmit()) }

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $model.askPath) {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xxl) {
                    if model.ask.exchanges.isEmpty && samples.isEmpty { suggestions }
                    if model.usesPublicRegistry {
                        ForEach(model.ask.exchanges) { exchange in
                            LiveExchangeView(exchange: exchange, offline: offline)
                        }
                    } else {
                        ForEach($samples) { $exchange in ExchangeView(exchange: $exchange) }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Space.margin)
                .padding(.vertical, Space.m)
            }
            .defaultScrollAnchor(.bottom, for: .sizeChanges)
            .scrollDismissesKeyboard(.interactively)
            .background(.canvas)
            .navigationTitle("Ask KilnWatch")
            .toolbar { ToolbarItem(placement: .topBarTrailing) { DataSourceLabel(text: model.dataSourceLabel) } }
            .safeAreaBar(edge: .bottom) {
                if let date = model.ask.submissionResumeDate {
                    TimelineView(.periodic(from: date, by: 60)) { _ in composer }
                } else { composer }
            }
            .navigationDestination(for: String.self) { KilnView(id: $0) }
            .onAppear {
                // Automatic playback is exclusively local sample data, never a live POST.
                if DemoOptions.bool("askPlay"), model.isAskTest, model.ask.exchanges.isEmpty {
                    model.askDraft = "How many kilns are flagged in Hapur?"; send()
                } else if DemoOptions.bool("askPlay"), !model.usesPublicRegistry, samples.isEmpty {
                    model.askDraft = AskScript.planDay.question; send()
                }
            }
        }
    }

    private var suggestions: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Text(model.usesPublicRegistry
                 ? "Ask about satellite-flagged registry records. Each question is independent; earlier questions aren't sent to the server."
                 : "Sample data · scripted answers demonstrate inspection planning and citation navigation.")
                .font(.body).foregroundStyle(.inkSecondary)
            Text("Try").eyebrow()
            let questions = model.usesPublicRegistry
                ? ["How many kilns are flagged in Hapur?", "What information is available in the registry?"]
                : AskScript.all.map(\.question)
            ForEach(questions, id: \.self) { question in
                Button { model.askDraft = question; composerFocused = true } label: {
                    HStack(alignment: .firstTextBaseline, spacing: Space.s) {
                        Text(question).font(.body).foregroundStyle(.ink).multilineTextAlignment(.leading)
                        Spacer(minLength: Space.xs)
                        Image(systemName: "arrow.up.right").font(.footnote.weight(.semibold)).foregroundStyle(.inkSecondary).accessibilityHidden(true)
                    }
                    .frame(minHeight: 44).card()
                }
                .buttonStyle(.plain).disabled(offline || sending)
            }
        }
    }

    private var composer: some View {
        @Bindable var model = model
        return VStack(alignment: .leading, spacing: Space.xs) {
            if offline { QuietBanner(text: "Offline · Ask needs a connection", systemImage: "wifi.slash") }
            if model.isAskTest { Text("Sample data · local Ask test response").font(.footnote).foregroundStyle(.inkSecondary) }
            #if DEBUG
            if offline, DemoOptions.string("askDemo") == "offlineRecovery" {
                Button("Restore test connection") { model.askConnectivity.restoreTestConnection() }.buttonStyle(.bordered)
            }
            #endif
            HStack(alignment: .bottom, spacing: Space.xs) {
                TextField("Ask about any kiln…", text: $model.askDraft, axis: .vertical)
                    .lineLimit(1...4).focused($composerFocused).submitLabel(.send)
                    .onSubmit { send() }.padding(.vertical, Space.s)
                    .accessibilityIdentifier("ask-composer")
                    .disabled(offline)
                Button { send() } label: {
                    Image(systemName: "arrow.up").font(.body.weight(.semibold)).foregroundStyle(.canvas)
                        .padding(Space.xxs).frame(minWidth: 36, minHeight: 36).background(.ink, in: .circle)
                        .frame(minWidth: 44, minHeight: 44).contentShape(.circle)
                }
                .buttonStyle(.plain).accessibilityLabel("Send").accessibilityIdentifier("ask-send").disabled(!canSend)
            }
            .padding(.leading, Space.m).padding(.trailing, Space.xxs)
            .glassEffect(.regular, in: .rect(cornerRadius: 26, style: .continuous))
            if !model.askDraft.isEmpty {
                Text("\(model.askDraft.trimmingCharacters(in: .whitespacesAndNewlines).unicodeScalars.count)/500 characters")
                    .font(.caption.monospacedDigit()).foregroundStyle(.inkSecondary)
                if let error = model.ask.validation { Text(error.message).font(.footnote).foregroundStyle(.ink) }
            }
            Text("Answers cite registry records. Agents never record verdicts.")
                .font(.footnote).foregroundStyle(.inkSecondary).padding(.horizontal, Space.xs)
        }
        .padding(.horizontal, Space.margin).padding(.bottom, Space.xs)
    }

    private func send() {
        guard canSend else { return }
        if model.usesPublicRegistry { _ = model.ask.send() }
        else {
            let question = model.askDraft.trimmingCharacters(in: .whitespacesAndNewlines)
            samples.append(Exchange(question: question, script: AskScript.matching(question)))
            model.askDraft = ""
        }
        composerFocused = false
    }
}

private struct QuestionBubble: View {
    let question: String
    var body: some View {
        Text(question).font(.body).foregroundStyle(.ink)
            .typesettingLanguage(.explicit(.init(identifier: "zxx")))
            .padding(.horizontal, Space.m).padding(.vertical, Space.s)
            .background(.surface2, in: .rect(cornerRadius: Radius.card, style: .continuous))
            .frame(maxWidth: .infinity, alignment: .trailing).padding(.leading, Space.xl)
            .accessibilityLabel("You asked: \(question)")
    }
}

private struct LiveExchangeView: View {
    let exchange: AskExchange
    let offline: Bool
    @Environment(AppModel.self) private var model
    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            QuestionBubble(question: exchange.request.question)
            switch exchange.state {
            case .waiting:
                HStack(spacing: Space.s) {
                    ProgressView()
                    Text("Waiting for an answer…").font(.body).foregroundStyle(.inkSecondary)
                }
                Button("Cancel question") { model.ask.cancel() }.buttonStyle(.bordered)
            case .answered(let answer):
                LiveToolCallTrace(steps: answer.steps)
                if answer.fallback { Text("Registry fallback").eyebrow() }
                CitationAnswerText(text: answer.answer.replacingOccurrences(of: "**", with: ""), citations: answer.uniqueCitations)
                Text(answer.disclaimer).font(.footnote).foregroundStyle(.inkSecondary)
            case .failed(let error, let retryAfter):
                Text(error.message).font(.body).foregroundStyle(.ink)
                if case .service(429, let detail) = error, detail?.code == "daily_cap_reached" {
                    Text("The shared limit resets each day at midnight UTC.").font(.footnote).foregroundStyle(.inkSecondary)
                }
                if error.canRetry {
                    TimelineView(.periodic(from: retryAfter, by: 1)) { context in
                        Button("Retry") { _ = model.ask.retry(exchange.id) }
                            .buttonStyle(.bordered).disabled(offline || model.ask.isSending || model.ask.submissionResumeDate != nil || context.date < retryAfter)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct LiveToolCallTrace: View {
    let steps: [AskStep]
    var body: some View {
        if !steps.isEmpty {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: Space.s) {
                    ForEach(Array(steps.enumerated()), id: \.offset) { _, step in
                        HStack(alignment: .top, spacing: Space.xs) {
                            Image(systemName: step.ok ? "checkmark.circle" : "exclamationmark.circle").accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: Space.xxs) {
                                Text(step.label).font(.footnote.weight(.semibold))
                                Text(step.summary).font(.footnote)
                                if !step.ok { Text("Tool input wasn't accepted").font(.footnote) }
                            }
                        }
                        .foregroundStyle(.inkSecondary)
                        .accessibilityElement(children: .combine)
                    }
                }.padding(.top, Space.xs)
            } label: { Text(steps.count == 1 ? "1 step" : "\(steps.count) steps").font(.footnote.weight(.semibold)).foregroundStyle(.inkSecondary) }
            .tint(.inkSecondary)
        }
    }
}

/// Native text wrapping preserves punctuation/newlines and supports long IDs at AX sizes.
/// Only the server-returned citation list can create links or chips.
private struct CitationAnswerText: View {
    let text: String
    let citations: [String]
    @Environment(\.openURL) private var openURL
    private var attributed: AttributedString {
        var result = AttributedString(text)
        for id in citations {
            var search = result.startIndex..<result.endIndex
            while let range = result[search].range(of: id) {
                result[range].link = CitationChip.url(for: id)
                result[range].font = .body.monospaced()
                search = range.upperBound..<result.endIndex
            }
        }
        return result
    }
    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            Text(attributed).font(.body).foregroundStyle(.ink).tint(.clay)
                .typesettingLanguage(.explicit(.init(identifier: "zxx")))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityActions {
                    ForEach(citations, id: \.self) { id in Button("Open \(id)") { openURL(CitationChip.url(for: id)) } }
                }
            ForEach(citations, id: \.self) { id in CitationChip(id: id) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

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
            QuestionBubble(question: exchange.question)
            ToolCallTrace(steps: exchange.script.steps, completed: exchange.completedSteps, isDone: exchange.isDone)
            if exchange.revealedTokens > 0 {
                let tokens = exchange.script.tokens
                let text = reduceMotion ? exchange.script.plainAnswer : tokens.prefix(exchange.revealedTokens).map { token in
                    switch token { case .word(let word): word; case .cite(let id, let trailing): id + trailing }
                }.joined(separator: " ")
                CitationAnswerText(text: text, citations: Array(Set(tokens.prefix(exchange.revealedTokens).compactMap(\.citation))).sorted())
                    .accessibilityLabel(exchange.script.plainAnswer)
            }
            if exchange.isDone {
                Text("Sample answer. Answers cite registry records. Agents never record verdicts.").font(.footnote).foregroundStyle(.inkSecondary)
            }
        }
        .task { await play() }
        .onChange(of: reduceMotion) { _, enabled in if enabled { finish() } }
    }
    private func finish() {
        exchange.completedSteps = exchange.script.steps.count
        exchange.revealedTokens = exchange.script.tokens.count; exchange.isDone = true
    }
    private func play() async {
        guard !exchange.isDone else { return }
        if reduceMotion { finish(); return }
        do {
            while exchange.completedSteps < exchange.script.steps.count {
                try await Task.sleep(for: .milliseconds(550))
                guard !exchange.isDone else { return }
                withAnimation(Motion.select.animation(reduceMotion: false)) { exchange.completedSteps += 1 }
            }
            while exchange.revealedTokens < exchange.script.tokens.count {
                try await Task.sleep(for: .milliseconds(45))
                guard !exchange.isDone else { return }
                exchange.revealedTokens += 1
            }
            exchange.isDone = true
        } catch { /* View cancellation pauses the sample; re-entry resumes it. */ }
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
