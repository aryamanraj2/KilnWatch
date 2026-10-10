import KilnWatchCore
import SwiftUI

/// Assessed modelled residents. Missing assessment has no figures or age-group substitutes.
struct ExposureBlock: View {
    let exposure: Exposure?
    var bufferRadiusM: Int?
    var modelled = false
    var sample = false

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        if let exposure {
        VStack(alignment: .leading, spacing: Space.s) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: Space.xs) { figure(exposure.people) }
                VStack(alignment: .leading, spacing: 0) { figure(exposure.people) }
            }
            Text("\(exposure.childrenUnderFive.grouped) under 5 · \(exposure.adultsOverSixty.grouped) over 60")
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.inkSecondary)
            if modelled {
                Text(Exposure.attribution).font(.footnote).foregroundStyle(.inkSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else if sample {
                Text("Sample population figures · illustrative, not an HRSL calculation")
                    .font(.footnote).foregroundStyle(.inkSecondary)
            }
        }
        .accessibilityElement(children: .combine)
        } else {
            Text("Population exposure not assessed")
                .font(.body)
                .foregroundStyle(.inkSecondary)
        }
    }

    @ViewBuilder private func figure(_ people: Int) -> some View {
        Text(people.grouped)
            .font(.largeTitle.weight(.semibold).monospacedDigit())
            .contentTransition(reduceMotion ? .identity : .numericText(value: Double(people)))
            .foregroundStyle(.ink)
        Text(modelled ? "modelled residents within 800 m of the kiln edge" : bufferRadiusM.map { "people within \($0) m" } ?? "people")
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
