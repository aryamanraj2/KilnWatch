import KilnWatchCore
import SwiftUI

/// Assessed population; a buffer label is only supplied for the fixture demonstration.
struct ExposureBlock: View {
    let exposure: Exposure?
    var bufferRadiusM: Int?

    @State private var appeared = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let exposure {
        let people = appeared ? exposure.people : 0
        VStack(alignment: .leading, spacing: Space.xxs) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Space.xs) { figure(people) }
                VStack(alignment: .leading, spacing: 0) { figure(people) }
            }
            Text("\(exposure.childrenUnderFive.grouped) under 5 · \(exposure.adultsOverSixty.grouped) over 60")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.inkSecondary)
        }
        .onScrollVisibilityChange(threshold: 0.6) { visible in
            guard visible, !appeared else { return }
            withAnimation(Motion.layout.animation(reduceMotion: reduceMotion)) { appeared = true }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "\(exposure.people.grouped) people\(bufferRadiusM.map { " within \($0) metres" } ?? ""), including \(exposure.childrenUnderFive.grouped) children under 5 and \(exposure.adultsOverSixty.grouped) adults over 60."
        )
        } else {
            Text("Population exposure not assessed")
                .font(.body)
                .foregroundStyle(.inkSecondary)
        }
    }

    @ViewBuilder private func figure(_ people: Int) -> some View {
        Text(people.grouped)
            .font(.largeTitle.weight(.semibold).monospacedDigit())
            .contentTransition(.numericText(value: Double(people)))
            .foregroundStyle(.ink)
        Text(bufferRadiusM.map { "people within \($0) m" } ?? "people")
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
