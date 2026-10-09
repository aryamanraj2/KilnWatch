import SwiftUI

/// People inside the 800 m buffer: one large figure, vulnerable groups below.
struct ExposureBlock: View {
    let exposure: Exposure

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let people = appeared ? exposure.peopleWithin800m : 0
        VStack(alignment: .leading, spacing: Space.xxs) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Space.xs) { figure(people) }
                VStack(alignment: .leading, spacing: 0) { figure(people) }
            }
            Text("\(exposure.childrenUnder5.grouped) under 5 · \(exposure.adultsOver60.grouped) over 60")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.inkSecondary)
        }
        .onScrollVisibilityChange(threshold: 0.6) { visible in
            guard visible, !appeared else { return }
            withAnimation(Motion.layout.animation(reduceMotion: reduceMotion)) { appeared = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(exposure.peopleWithin800m.grouped) people within 800 metres, including \(exposure.childrenUnder5.grouped) children under 5 and \(exposure.adultsOver60.grouped) adults over 60."
        )
    }

    @ViewBuilder private func figure(_ people: Int) -> some View {
        Text(people.grouped)
            .font(.largeTitle.weight(.semibold).monospacedDigit())
            .contentTransition(.numericText(value: Double(people)))
            .foregroundStyle(.ink)
        Text("people within 800 m")
            .font(.body)
            .foregroundStyle(.inkSecondary)
    }
}

#Preview {
    ExposureBlock(exposure: Mock.route[0].exposure)
        .card()
        .padding(Space.margin)
        .background(.canvas)
}
