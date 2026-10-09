import SwiftUI

/// Verdict submission only. Hold 1.2 s to fill the ring; releasing early reverses it.
/// VoiceOver and Switch Control submit through the default action without the hold.
struct HoldToConfirmButton: View {
    let title: String
    /// `.success` online, `.warning` when the verdict is queued offline.
    var feedback: SensoryFeedback = .success
    let action: () -> Void

    @State private var progress: CGFloat = 0
    @State private var pressing = false
    @State private var completed = false
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: Space.xs) {
            if completed {
                Image(systemName: "checkmark")
                    .transition(.symbolEffect(.drawOn))
            }
            Text(completed ? "Submitted" : title)
                .contentTransition(.opacity)
        }
        .font(.body.weight(.semibold))
        .foregroundStyle(.canvas)
        .frame(maxWidth: .infinity, minHeight: 56)
        .background(.ink, in: .capsule)
        .padding(Space.xs)
        .overlay {
            Capsule()
                .trim(from: 0, to: progress)
                .stroke(.ink, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .padding(1.5)
        }
        .scaleEffect(pressing && !reduceMotion ? 0.97 : 1)
        .opacity(isEnabled ? 1 : 0.4)
        .contentShape(.capsule)
        .onLongPressGesture(minimumDuration: 1.2, maximumDistance: 40) {
            complete()
        } onPressingChanged: { isPressing in
            guard !completed, isEnabled else { return }
            pressing = isPressing
            withAnimation(isPressing ? .linear(duration: 1.2) : .easeOut(duration: 0.3)) {
                progress = isPressing ? 1 : 0
            }
        }
        .sensoryFeedback(feedback, trigger: completed) { _, done in done }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(completed ? "Submitted" : title)
        .accessibilityHint("Touch and hold for one second")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { complete() }
        .accessibilityAction(named: "Submit verdict") { complete() }
        #if DEBUG
        .task(id: isEnabled) { await scriptedHold() }
        #endif
    }

    #if DEBUG
    /// `-autoplay hold`: an early release, then a full hold, for the screen recording.
    private func scriptedHold() async {
        guard isEnabled, UserDefaults.standard.string(forKey: "autoplay") == "hold" else { return }
        for duration in [0.6, 1.2] {
            try? await Task.sleep(for: .seconds(2.5))
            pressing = true
            withAnimation(.linear(duration: 1.2)) { progress = 1 }
            try? await Task.sleep(for: .seconds(duration))
            if duration < 1.2 {
                pressing = false
                withAnimation(.easeOut(duration: 0.3)) { progress = 0 }
            } else {
                complete()
            }
        }
    }
    #endif

    private func complete() {
        guard isEnabled, !completed else { return }
        withAnimation(Motion.confirm.animation(reduceMotion: reduceMotion)) {
            pressing = false
            progress = 1
            completed = true
        }
        action()
    }
}

#Preview {
    VStack(spacing: Space.xl) {
        HoldToConfirmButton(title: "Hold to submit verdict") {}
        HoldToConfirmButton(title: "Hold to submit verdict") {}.disabled(true)
    }
    .padding(Space.margin)
    .background(.canvas)
}
