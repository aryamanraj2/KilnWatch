import KilnWatchCore
import SwiftUI

/// Monospaced kiln ID with optional type and confidence ("FCBK · 0.82", or "likely CFCBK · 0.64").
struct KilnIDLabel: View {
    let kiln: Kiln
    var showsType = true
    var idFont: Font = .headline
    var predictionOnly = false
    var abbreviatesID = false

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Space.xs) { content }
            VStack(alignment: .leading, spacing: Space.xxs) { content }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    @ViewBuilder private var content: some View {
        Text(abbreviatesID && kiln.kilnId.count > 18 ? "\(kiln.kilnId.prefix(9))…\(kiln.kilnId.suffix(6))" : kiln.kilnId)
            .font(idFont.monospaced())
            .foregroundStyle(.ink)
        if showsType {
            Text(typeLine)
                .font(.subheadline.monospacedDigit())
                .foregroundStyle(.inkSecondary)
        }
    }

    private var typeLine: String {
        if predictionOnly { return "Predicted \(kiln.type.rawValue) · unverified" }
        let confidence = kiln.typeConfidence.formatted(.number.precision(.fractionLength(2)))
        return "\(kiln.typeIsCertain ? "" : "likely ")\(kiln.type.rawValue) · \(confidence)"
    }

    private var accessibilityText: String {
        guard showsType else { return "Kiln \(kiln.kilnId)" }
        if predictionOnly { return "Kiln \(kiln.kilnId), predicted \(kiln.type.rawValue), unverified" }
        return "Kiln \(kiln.kilnId), \(kiln.typeIsCertain ? "" : "likely ")\(kiln.type.rawValue), confidence \(kiln.typeConfidence.formatted(.percent))"
    }
}

#Preview {
    VStack(alignment: .leading, spacing: Space.m) {
        KilnIDLabel(kiln: Mock.route[0])
        KilnIDLabel(kiln: Mock.route[3])
        KilnIDLabel(kiln: Mock.route[0], showsType: false, idFont: .largeTitle)
    }
    .padding(Space.margin)
    .background(.canvas)
}
