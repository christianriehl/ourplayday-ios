import Combine
import Network

@MainActor
final class NetworkMonitor: ObservableObject {
    @Published private(set) var isConnected = true

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "playday.network-monitor")
    private let continuation: AsyncStream<Bool>.Continuation

    init() {
        let (stream, continuation) = AsyncStream<Bool>.makeStream()
        self.continuation = continuation

        monitor.pathUpdateHandler = { [continuation] path in
            continuation.yield(path.status == .satisfied)
        }
        monitor.start(queue: queue)

        Task {
            for await connected in stream {
                isConnected = connected
            }
        }
    }

    deinit {
        monitor.cancel()
        continuation.finish()
    }
}
