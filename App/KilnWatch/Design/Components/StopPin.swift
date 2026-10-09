import SwiftUI

/// Numbered route stop on the map. Ink disc; clay and 1.2× when selected. Pins enter staggered.
struct StopPin: View {
    let stop: Stop
    let isSelected: Bool
    let action: () -> Void

    @ScaledMetric(relativeTo: .subheadline) private var size: CGFloat = 30
    @State private var entered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            Text(stop.number, format: .number)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.canvas)
                .frame(width: size, height: size)
                .background(isSelected ? Color.clay : Color.ink, in: .circle)
                .overlay { Circle().strokeBorder(.canvas, lineWidth: 2) }
                .scaleEffect(isSelected && !reduceMotion ? 1.2 : 1)
                .frame(minWidth: 44, minHeight: 44)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .opacity(entered ? 1 : 0)
        .scaleEffect(entered || reduceMotion ? 1 : 0.6)
        .animation(Motion.select.animation(reduceMotion: reduceMotion), value: isSelected)
        .onAppear {
            withAnimation(Motion.select.animation(reduceMotion: reduceMotion).delay(Motion.stagger(stop.number - 1))) {
                entered = true
            }
        }
        .accessibilityLabel("Stop \(stop.number), \(stop.kilnID)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

#Preview {
    @Previewable @State var selected = 1
    HStack(spacing: Space.m) {
        ForEach(Mock.stops.prefix(4)) { stop in
            StopPin(stop: stop, isSelected: selected == stop.number) { selected = stop.number }
        }
    }
    .padding(Space.xxl)
    .background(.surface2)
}
