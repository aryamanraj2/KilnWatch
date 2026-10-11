import KilnWatchCore
import SwiftUI
import PhotosUI
import AVFoundation

/// The only way a kiln's status changes. Presented from Kiln at the large detent.
struct VerdictSheet: View {
    let kilnId: String

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var selection
    @State private var choice: KilnStatus?
    @State private var photos: [VerdictPhoto] = []
    @State private var location = ForegroundLocation()
    @Environment(\.scenePhase) private var scenePhase
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showCamera = false
    @State private var processingPhoto = false
    @State private var photoNotice: String?
    @State private var savedID: UUID?
    @State private var submitError: String?
    @State private var note = ""
    @FocusState private var noteFocused: Bool
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
                            .focused($noteFocused)
                            .accessibilityIdentifier("verdict-note")
                            .lineLimit(3...6)
                            .onChange(of: note) { _, value in note = String(String.UnicodeScalarView(value.unicodeScalars.prefix(2000))) }
                            .padding(Space.s)
                            .background(.surface, in: .inner)
                    }
                    Text("\(note.unicodeScalars.count) / 2000 characters").font(.footnote.monospacedDigit()).foregroundStyle(.inkSecondary)
                    Text("This changes \(kilnId)'s status for everyone.")
                        .font(.footnote)
                        .foregroundStyle(.inkSecondary)
                }
                .padding(.horizontal, Space.margin)
                .padding(.top, Space.s)
                .padding(.bottom, Space.xl)
                .disabled(saved)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(.canvas)
            .navigationTitle("Record verdict")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .keyboard) {
                    Spacer()
                    Button("Done") { noteFocused = false }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button(saved ? "Close" : "Cancel", role: saved ? .close : .cancel) { dismiss() }
                }
            }
            .safeAreaBar(edge: .bottom) { submitBar }
        }
        .presentationDetents([.large])
        .interactiveDismissDisabled((choice != nil || !photos.isEmpty || !note.isEmpty) && !saved)
        .fullScreenCover(isPresented: $showCamera) {
            VerdictCamera { data in
                showCamera = false
                if let data {
                    processingPhoto = true
                    Task { await attach(data); processingPhoto = false }
                }
            }.ignoresSafeArea()
        }
        .task(id: selectedPhoto) {
            guard let selectedPhoto else { return }
            processingPhoto = true
            defer { processingPhoto = false; self.selectedPhoto = nil }
            do {
                if let data = try await selectedPhoto.loadTransferable(type: Data.self) { await attach(data) }
                else { photoNotice = "This photo could not be opened. Choose another." }
            } catch { photoNotice = "This photo could not be opened. Choose another." }
        }
        .onChange(of: scenePhase, initial: true) { _, phase in
            location.setActive(phase == .active)
            if phase == .active { location.recenter() }
        }
        .onAppear { location.setActive(scenePhase == .active); if scenePhase == .active { location.recenter() } }
        .onDisappear { location.setActive(false) }
        .onChange(of: saved) { _, saved in if saved { Task { await model.flushVerdicts() } } }

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
            Text("\(photos.count) photo\(photos.count == 1 ? "" : "s") · \(photos.isEmpty ? "up to 8" : "geotagged")").eyebrow()
            if let photoNotice { Text(photoNotice).font(.footnote).foregroundStyle(.inkSecondary) }
            if location.fix == nil {
                Text("Location unavailable · photo can't be geotagged").font(.footnote).foregroundStyle(.inkSecondary)
                Button("Try location again") { location.recenter() }.frame(minHeight: 44)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: Space.s, alignment: .top)], spacing: Space.s) {
                ForEach(photos) { photo in
                    VStack(alignment: .leading, spacing: Space.xxs) {
                        if let image = UIImage(data: photo.jpeg) {
                            Image(uiImage: image).resizable().scaledToFit()
                                .frame(maxWidth: .infinity).clipShape(.inner).accessibilityLabel("Geotagged site photo")
                        }
                        Text(geotag(photo.record)).font(.caption2.monospaced()).foregroundStyle(.inkSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Button("Remove photo", role: .destructive) { photos.removeAll { $0.id == photo.id } }.frame(minHeight: 44)
                    }
                }
                if photos.count < 8 {
                    photoButton.disabled(processingPhoto)
                }
            }
        }
    }

    private var cameraAvailable: Bool {
        #if targetEnvironment(simulator)
        false
        #else
        UIImagePickerController.isSourceTypeAvailable(.camera)
        #endif
    }

    @ViewBuilder private var photoButton: some View {
        let label = photoButtonLabel
        if cameraAvailable {
            Button(action: addPhoto) { label }.buttonStyle(.plain)
        } else {
            PhotosPicker(selection: $selectedPhoto, matching: .images) { label }
                .buttonStyle(.plain)
                .simultaneousGesture(TapGesture().onEnded { location.recenter(); photoNotice = nil })
        }
    }

    private var photoButtonLabel: VerdictPhotoButtonLabel { VerdictPhotoButtonLabel(preparing: processingPhoto) }

    private func geotag(_ photo: Photo) -> String {
        let lat = photo.latitude.formatted(.number.precision(.fractionLength(4)))
        let lon = photo.longitude.formatted(.number.precision(.fractionLength(4)))
        var format = Date.FormatStyle.dateTime.hour().minute()
        format.timeZone = TimeZone(identifier: "Asia/Kolkata")!
        let time = photo.takenAt.formatted(format)
        return "\(lat), \(lon) · ±\(photo.horizontalAccuracyM.formatted(.number.precision(.fractionLength(0)))) m · \(time) IST"
    }

    private func addPhoto() {
        location.recenter()
        photoNotice = nil
        Task {
            var allowed = AVCaptureDevice.authorizationStatus(for: .video) == .authorized
            if AVCaptureDevice.authorizationStatus(for: .video) == .notDetermined { allowed = await AVCaptureDevice.requestAccess(for: .video) }
            if allowed { showCamera = true }
            else { photoNotice = "Camera access unavailable. Allow it in Settings to take a site photo." }
        }
    }

    private func attach(_ data: Data) async {
        let captureTime = Date.now
        guard photos.count < 8, let fix = location.fix,
              captureTime.timeIntervalSince(fix.takenAt) >= -10,
              captureTime.timeIntervalSince(fix.takenAt) <= 120 else {
            photoNotice = "Location unavailable · photo can't be geotagged"; return
        }
        guard let jpeg = await VerdictJPEG.prepare(data) else { photoNotice = "This photo could not be prepared. Choose another."; return }
        guard photos.count < 8, !saved else { return }
        let record = Photo(latitude: fix.latitude, longitude: fix.longitude, horizontalAccuracyM: fix.horizontalAccuracyM, takenAt: captureTime)
        photos.append(VerdictPhoto(record: record, jpeg: jpeg))
        photoNotice = nil
    }

    // MARK: Submit

    private var submitBar: some View {
        VStack(spacing: Space.xs) {
            HoldToConfirmButton(title: "Hold to submit verdict", feedback: model.askConnectivity.isOffline || model.isOffline ? .warning : .success) {
                guard let choice, let outcome = Verdict.Outcome(rawValue: choice.rawValue) else { return false }
                let verdict = Verdict(kilnId: kilnId, outcome: outcome, photos: photos.map(\.record), note: note)
                guard await model.enqueueVerdict(verdict, photos: Dictionary(uniqueKeysWithValues: photos.map { ($0.id, $0.jpeg) })) else {
                    submitError = "The verdict could not be saved on this phone. Try again."; return false
                }
                savedID = verdict.id
                saved = true
                AccessibilityNotification.Announcement(savedText).post()
                return true
            }
            .disabled(choice == nil || processingPhoto || saved)
            if let submitError { Text(submitError).font(.footnote).foregroundStyle(.ink) }
            Text(saved ? savedText : (choice == nil ? "Choose a verdict to continue" : "Hold for one second to submit"))
                .font(.footnote.weight(saved ? .semibold : .regular))
                .foregroundStyle(saved ? Color.ink : Color.inkSecondary)
                .contentTransition(.opacity)
        }
        .padding(.horizontal, Space.margin)
        .padding(.vertical, Space.xs)
    }

    private var savedText: String {
        guard model.usesPublicRegistry else { return "Sample verdict recorded" }
        if let entry = model.verdictEntries.first(where: { $0.id == savedID }) {
            return entry.rejected == true ? "Verdict rejected · \(entry.lastError ?? "Could not be accepted")" : entry.lastError ?? "Verdict saved · will sync when online"
        }
        return saved ? "Verdict recorded" : "Verdict saved · will sync when online"
    }
}

private struct VerdictPhotoButtonLabel: View, Sendable {
    let preparing: Bool
    var body: some View {
        HStack(spacing: Space.xs) {
            Image(systemName: "camera")
            Text(preparing ? "Preparing photo" : "Add photo")
        }
        .font(.subheadline.weight(.medium)).foregroundStyle(.ink)
        .frame(maxWidth: .infinity, minHeight: 104)
        .background(.surface2, in: .inner)
        .contentShape(.rect)
    }
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
