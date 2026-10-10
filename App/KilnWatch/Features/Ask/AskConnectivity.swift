import Network
import Observation

/// Path observation only describes connectivity; a satisfied path never promises API availability.
@MainActor @Observable final class AskConnectivity {
    private(set) var isOffline = false
    @ObservationIgnored private let monitor: NWPathMonitor?

    init(observing: Bool) {
        #if DEBUG
        isOffline = ["offline", "offlineRecovery"].contains(DemoOptions.string("askDemo") ?? "")
        #endif
        guard observing else { monitor = nil; return }
        let monitor = NWPathMonitor()
        self.monitor = monitor
        monitor.pathUpdateHandler = { [weak self] path in
            let offline = path.status == .unsatisfied
            Task { @MainActor [weak self] in self?.isOffline = offline }
        }
        monitor.start(queue: DispatchQueue(label: "KilnWatch.AskConnectivity"))
    }
    #if DEBUG
    func restoreTestConnection() { isOffline = false }
    #endif
    deinit { monitor?.cancel() }
}
