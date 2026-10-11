import KilnWatchCore
import SwiftUI

/// Numbered route stop on the map. Ink disc; clay and 1.2× when selected. Pins enter staggered.
struct StopPin: View {
    let stop: Stop
    let isSelected: Bool
    var labelSide: HorizontalEdge? = nil
    let action: () -> Void

    @ScaledMetric(relativeTo: .subheadline) private var size: CGFloat = 30
    @State private var entered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            HStack(spacing: 0) {
                if labelSide == .trailing { leader }
                Text(stop.order, format: .number)
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .foregroundStyle(isSelected ? Color.canvas : Color.ink)
                    .frame(width: size, height: size)
                    .background(isSelected ? Color.clay : Color.surface, in: .circle)
                    .overlay { Circle().strokeBorder(isSelected ? Color.clay : Color.inkSecondary, lineWidth: 1) }
                    .scaleEffect(isSelected && !reduceMotion ? 1.12 : 1)
                    .frame(minWidth: 44, minHeight: 44)
                    .contentShape(.circle)
                if labelSide == .leading { leader }
            }
        }
        .buttonStyle(.plain)
        .opacity(entered ? 1 : 0)
        .scaleEffect(entered || reduceMotion ? 1 : 0.6)
        .animation(Motion.select.animation(reduceMotion: reduceMotion), value: isSelected)
        .onAppear {
            withAnimation(Motion.select.animation(reduceMotion: reduceMotion).delay(Motion.stagger(stop.order - 1))) {
                entered = true
            }
        }
        .accessibilityLabel("Stop \(stop.order), \(stop.kilnId)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
    private var leader: some View {
        Rectangle().fill(isSelected ? Color.clay : Color.inkSecondary).frame(width: Space.s, height: 1)
            .overlay(alignment: labelSide == .leading ? .trailing : .leading) {
                Circle().fill(isSelected ? Color.clay : Color.inkSecondary).frame(width: 4, height: 4)
            }.accessibilityHidden(true)
    }
}

#Preview {
    @Previewable @State var selected = 1
    HStack(spacing: Space.m) {
        ForEach(Mock.stops.prefix(4)) { stop in
            StopPin(stop: stop, isSelected: selected == stop.order) { selected = stop.order }
        }
    }
    .padding(Space.xxl)
    .background(.surface2)
}
