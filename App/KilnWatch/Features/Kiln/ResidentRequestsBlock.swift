import KilnWatchCore
import SwiftUI

/// A resident signal, presented independently from satellite flags and inspector verdicts.
struct ResidentRequestsBlock: View {
    let requests: ResidentRequests?
    @State private var expanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: Space.m) {
            Label {
                Text(summary).font(.headline).monospacedDigit()
            } icon: {
                Image(systemName: "person.2").accessibilityHidden(true)
            }
            .foregroundStyle(.ink)
            if let requests, requests.count > 0 {
                Text("Anonymous resident reports · not verified. Requests do not change the kiln’s status or guarantee an inspection.")
                    .font(.footnote).foregroundStyle(.inkSecondary)
                DisclosureGroup("Concerns, distance and latest request", isExpanded: $expanded) {
                    Text("\(requests.within1Km.formatted()) say they live within 1 km · not verified")
                        .font(.subheadline).monospacedDigit().foregroundStyle(.inkSecondary)
                    VStack(alignment: .leading, spacing: Space.s) {
                        concern("Smoke or ash", count: requests.concerns.smokeOrAsh)
                        concern("Near homes", count: requests.concerns.nearHomes)
                        concern("Near a school or hospital", count: requests.concerns.nearSchoolOrHospital)
                        concern("Other concerns", count: requests.concerns.other)
                    }
                    if let date = lastRequestLabel(requests.lastRequestOn) {
                        Text("Last request \(date)").font(.footnote).foregroundStyle(.inkSecondary)
                    }
                }.tint(.ink).font(.subheadline)
                    .animation(Motion.layout.animation(reduceMotion: reduceMotion), value: expanded)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityIdentifier("resident-requests")
    }

    private var summary: String {
        guard let requests else { return "Resident request data unavailable" }
        if requests.count == 0 { return "No resident requests yet" }
        return "\(requests.count.formatted()) inspection \(requests.count == 1 ? "request" : "requests")"
    }

    private func concern(_ label: String, count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: Space.s) {
            Text(label).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Space.s)
            Text(count, format: .number).monospacedDigit()
        }
        .font(.subheadline).foregroundStyle(.inkSecondary)
        .accessibilityElement(children: .combine)
    }

    private func lastRequestLabel(_ value: String?) -> String? {
        guard let value else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_GB")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let date = formatter.date(from: value), formatter.string(from: date) == value else { return nil }
        formatter.dateFormat = "d MMM"
        return formatter.string(from: date)
    }
}
