import KilnWatchCore
import SwiftUI

/// Pending choices remain separate from the registry's recorded status.
struct VerdictStatusView: View {
    let kiln: Kiln
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xxs) {
            StatusBadge(status: model.status(for: kiln), detailed: model.usesPublicRegistry)
            if let line = model.recordedLine(kiln) {
                Label(line, systemImage: "checkmark.circle").font(.footnote).foregroundStyle(.inkSecondary)
            }
            PendingVerdictView(kilnId: kiln.kilnId)
        }
    }
}

/// Available even when an offline relaunch cannot fetch the kiln record.
struct PendingVerdictView: View {
    let kilnId: String
    @Environment(AppModel.self) private var model
    @State private var discard = false

    @ViewBuilder var body: some View {
        if let pending = model.pendingVerdict(kilnId) {
            VStack(alignment: .leading, spacing: Space.xxs) {
                Label(pending.rejected == true ? "Verdict rejected" : "Verdict pending sync", systemImage: pending.rejected == true ? "exclamationmark.circle" : "clock")
                    .font(.footnote.weight(.semibold)).foregroundStyle(.inkSecondary)
                Text("\(KilnStatus(rawValue: pending.verdict.outcome.rawValue).label) · pending")
                    .font(.footnote).foregroundStyle(.inkSecondary)
                if let message = pending.lastError {
                    Text(message).font(.footnote).foregroundStyle(.inkSecondary)
                }
                if pending.rejected == true {
                    Button("Discard", role: .destructive) { discard = true }.frame(minHeight: 44)
                        .confirmationDialog("Discard this rejected verdict and its saved photos?", isPresented: $discard, titleVisibility: .visible) {
                            Button("Discard verdict", role: .destructive) { Task { await model.discardVerdict(pending.id) } }
                            Button("Keep verdict", role: .cancel) {}
                        }
                }
            }
        }
    }
}
