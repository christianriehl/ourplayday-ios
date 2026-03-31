import Combine
import Network

@MainActor
final class NetworkMonitor: ObservableObject {
    @Published private(set) var isConnected = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "playday.network-monitor")

    init() {
        monitor.start(queue: queue)
        Task {
            for await path in monitor.paths {
                isConnected = path.status == .satisfied
            }
        }
    }

    deinit {
        monitor.cancel()
    }
}
