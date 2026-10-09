import KilnWatchCore
import SwiftUI

/// The only way a kiln's status changes. Presented from Kiln at the large detent.
struct VerdictSheet: View {
    let kilnId: String

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selection
    @State private var choice: KilnStatus?
    @State private var photos: [SitePhoto] = [SitePhoto(asset: "sitePhoto1", time: "10:42"), SitePhoto(asset: "sitePhoto2", time: "10:44")]
    @State private var note = ""
    @State private var saved = false
    @Environment(\.dynamicTypeSize) private var typeSize

    private static let options: [KilnStatus] = [.confirmed, .compliant, .notAKiln, .closed]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Space.xl) {
                    Text("\(Text(kilnId).monospaced()) · \(stopLine)")
                        .font(.headline)
                        .foregroundStyle(.ink)
                    VStack(spacing: Space.xs) {
                        ForEach(Self.options, id: \.self) { status in option(status) }
                    }
                    .sensoryFeedback(.selection, trigger: choice)
                    photoSection
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text("Note").eyebrow()
                        TextField("Chimney type, fuel on site, anything unusual", text: $note, axis: .vertical)
                            .lineLimit(3...6)
                            .padding(Space.s)
                            .background(.surface, in: .inner)
                    }
                    Text("This changes \(kilnId)'s status for everyone.")
                        .font(.footnote)
                        .foregroundStyle(.inkSecondary)
                }
                .padding(.horizontal, Space.margin)
                .padding(.bottom, Space.xl)
                .disabled(saved)
            }
            .background(.canvas)
            .navigationTitle("Record verdict")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(saved ? "Close" : "Cancel", role: saved ? .close : .cancel) { dismiss() }
                }
            }
            .safeAreaBar(edge: .bottom) { submitBar }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled(choice != nil && !saved)
        #if DEBUG
        .task {
            // `-verdictChoice confirmed` preselects a row for screenshots.
            guard let raw = UserDefaults.standard.string(forKey: "verdictChoice") else { return }
            try? await Task.sleep(for: .seconds(1))
            withAnimation(Motion.select.animation(reduceMotion: reduceMotion)) { choice = KilnStatus(rawValue: raw) }
        }
        #endif
    }

    private var stopLine: String {
        model.stopNumber(for: kilnId).map { "stop \($0) of \(model.stops.count)" } ?? (model.kiln(kilnId)?.district ?? "District unavailable")
    }

    // MARK: Options

    private func option(_ status: KilnStatus) -> some View {
        let selected = choice == status
        return Button {
            withAnimation(Motion.select.animation(reduceMotion: reduceMotion)) { choice = status }
        } label: {
            let layout = typeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(alignment: .leading, spacing: Space.xs))
                : AnyLayout(HStackLayout(spacing: Space.s))
            layout {
                Image(systemName: status.symbol)
                    .font(.title3)
                    .foregroundStyle(status.color)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(status.verdictTitle)
                        .font(.headline)
                        .foregroundStyle(.ink)
                    Text(status.meaning)
                        .font(.subheadline)
                        .foregroundStyle(.inkSecondary)
                }
                Spacer(minLength: Space.xs)
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Color.ink : Color.inkSecondary)
                    .contentTransition(.symbolEffect(.replace))
            }
            .padding(Space.m)
            .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading)
            .background(.surface, in: .inner)
            .overlay {
                if selected {
                    ConcentricRectangle.inner
                        .stroke(.ink, lineWidth: 2)
                        .padding(1)
                        .matchedGeometryEffect(id: "selection", in: selection)
                }
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(status.verdictTitle). \(status.meaning)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    // MARK: Photos

    private var photoSection: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            Text("\(photos.count) photos · geotagged").eyebrow()
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Space.s, alignment: .top)], spacing: Space.s) {
                ForEach(photos) { photo in
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        Image(photo.asset)
                            .resizable()
                            .scaledToFill()
                            .frame(minWidth: 0, maxWidth: .infinity)
                            .aspectRatio(1, contentMode: .fit)
                            .clipShape(.inner)
                            .accessibilityLabel("Site photo taken at \(photo.time)")
                        Text(geotag(photo))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.inkSecondary)
                    }
                }
                if photos.count < 6 {
                    Button(action: addPhoto) {
                        Label("Add photo", systemImage: "camera")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(.ink)
                            .frame(maxWidth: .infinity)
                            .aspectRatio(1, contentMode: .fit)
                            .background(.surface2, in: .inner)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func geotag(_ photo: SitePhoto) -> String {
        guard let c = model.kiln(kilnId)?.coordinate else { return "Location unavailable" }
        let lat = c.latitude.formatted(.number.precision(.fractionLength(4)))
        let lon = c.longitude.formatted(.number.precision(.fractionLength(4)))
        return "\(lat)° N, \(lon)° E · ±6 m · \(photo.time)"
    }

    private func addPhoto() {
        let minute = 44 + photos.count * 2
        photos.append(SitePhoto(asset: photos.count.isMultiple(of: 2) ? "sitePhoto1" : "sitePhoto2", time: "10:\(minute)"))
    }

    // MARK: Submit

    private var submitBar: some View {
        VStack(spacing: Space.xs) {
            HoldToConfirmButton(title: "Hold to submit verdict", feedback: model.isOffline ? .warning : .success) {
                guard let choice else { return }
                model.recordVerdict(choice, for: kilnId)
                saved = true
                AccessibilityNotification.Announcement(savedText).post()
            }
            .disabled(choice == nil)
            Text(saved ? savedText : (choice == nil ? "Choose a verdict to continue" : "Hold for one second to submit"))
                .font(.footnote.weight(saved ? .semibold : .regular))
                .foregroundStyle(saved ? Color.ink : Color.inkSecondary)
                .contentTransition(.opacity)
        }
        .padding(.horizontal, Space.margin)
        .padding(.vertical, Space.xs)
    }

    private var savedText: String {
        model.isOffline ? "Verdict saved · will sync when online" : "Verdict recorded"
    }
}

private struct SitePhoto: Identifiable {
    let id = UUID()
    let asset: String
    let time: String
}

extension KilnStatus {
    var verdictTitle: String {
        self == .closed ? "Closed / not firing" : label
    }

    var meaning: String {
        switch self {
        case .confirmed: "The kiln breaks the flagged rules as measured."
        case .compliant: "The kiln meets every flagged rule."
        case .notAKiln: "The detection is another structure."
        case .closed: "The kiln stands but is not operating."
        case .flagged: "Flagged by satellite · pending inspection"
        case .unknown: "Status not recognized. Confirm on site."
        }
    }
}

#Preview {
    Color.canvas.sheet(isPresented: .constant(true)) {
        VerdictSheet(kilnId: "KW-0412")
    }
    .environment(AppModel())
}
