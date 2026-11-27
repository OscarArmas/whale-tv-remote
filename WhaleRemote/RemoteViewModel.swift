import Foundation
import Darwin

@MainActor
final class RemoteViewModel: ObservableObject {
    enum Connection { case disconnected, connecting, connected, failed }

    @Published private(set) var connection = Connection.disconnected
    @Published private(set) var devices: [TvDevice] = []
    @Published private(set) var isSearching = false
    @Published private(set) var selected: TvDevice?
    @Published private(set) var lastError: String?
    @Published private(set) var lastKey: String?
    @Published private(set) var inFlight = 0

    private let discover: () async -> [TvDevice]
    private let makeRemote: (URL, URL?) -> DlnaRemote
    private var remote: DlnaRemote?
    private var heartbeat: Task<Void, Never>?
    private var commands: [Task<Void, Never>] = []
    private var moveTask: Task<Void, Never>?
    private var pendingX = 0
    private var pendingY = 0

    init(discover: @escaping () async -> [TvDevice] = { await SsdpClient.search() },
         makeRemote: @escaping (URL, URL?) -> DlnaRemote = { DlnaRemote(controlURL: $0, renderingURL: $1) }) {
        self.discover = discover
        self.makeRemote = makeRemote
    }

    var isConnected: Bool { connection == .connected }

    func search() async {
        guard !isSearching else { return }
        isSearching = true
        lastError = nil
        devices = await discover()
        isSearching = false
    }

    func connect(_ device: TvDevice) async {
        disconnect()
        guard let url = device.avTransportControlURL else {
            fail(RemoteError.noControlURL)
            return
        }
        let client = makeRemote(url, device.renderingControlURL)
        let ip = Self.guessLocalIPv4(preferringHost: device.host) ?? "0.0.0.0"
        remote = client
        selected = device
        connection = .connecting
        heartbeat = Task { [weak self] in
            do {
                while !Task.isCancelled {
                    _ = try await client.sendHeartbeat(localIP: ip)
                    guard !Task.isCancelled, self?.remote === client else { return }
                    self?.connection = .connected
                    try await Task.sleep(nanoseconds: 10_000_000_000)
                }
            } catch {
                guard !Task.isCancelled, self?.remote === client else { return }
                self?.fail(error)
            }
        }
    }

    private func fail(_ error: Error) {
        disconnect()
        connection = .failed
        lastError = error.localizedDescription
    }

    func disconnect() {
        heartbeat?.cancel()
        heartbeat = nil
        commands.forEach { $0.cancel() }
        commands.removeAll()
        moveTask?.cancel()
        moveTask = nil
        pendingX = 0
        pendingY = 0
        inFlight = 0
        remote = nil
        selected = nil
        lastKey = nil
        lastError = nil
        connection = .disconnected
    }

    // Keep button presses in order, including both halves of a volume change.
    private func enqueue(label: String, operation: @escaping (DlnaRemote) async throws -> Void) {
        guard isConnected, let client = remote else { return }
        let previous = commands.last
        inFlight += 1
        commands.append(Task {
            await previous?.value
            guard !Task.isCancelled, remote === client else { return }
            do {
                try await operation(client)
                guard !Task.isCancelled, remote === client else { return }
                lastKey = label
                lastError = nil
            } catch {
                guard !Task.isCancelled, remote === client else { return }
                lastError = error.localizedDescription
            }
            commands.removeFirst()
            inFlight -= 1
        })
    }

    func press(_ key: String) {
        enqueue(label: key) { client in
            switch key {
            case RemoteKeys.volumeUp: _ = try await client.volumeUp()
            case RemoteKeys.volumeDown: _ = try await client.volumeDown()
            case RemoteKeys.mute: _ = try await client.toggleMute()
            default: _ = try await client.sendKey(key)
            }
        }
    }

    func sendText(_ text: String, pressEnter: Bool = true) {
        guard !text.isEmpty else { return }
        enqueue(label: "Text sent · \(text.count) characters") { client in
            _ = try await client.sendString(text)
            if pressEnter {
                try await Task.sleep(nanoseconds: 150_000_000)
                _ = try await client.sendKey(RemoteKeys.enter)
            }
        }
    }

    func move(x: Int, y: Int) {
        guard isConnected, let client = remote else { return }
        pendingX += x
        pendingY += y
        guard moveTask == nil else { return }
        moveTask = Task {
            while !Task.isCancelled, remote === client {
                let (dx, dy) = (pendingX, pendingY)
                pendingX = 0
                pendingY = 0
                if dx == 0 && dy == 0 { break }
                do {
                    _ = try await client.sendMouseMove(x: dx, y: dy)
                } catch {
                    guard !Task.isCancelled, remote === client else { return }
                    lastError = error.localizedDescription
                }
            }
            if !Task.isCancelled, remote === client { moveTask = nil }
        }
    }

    /// IPv4 of the active interface. Prefer the one that shares the /24 subnet
    /// with the TV, so the heartbeat URL resolves correctly.
    private static func guessLocalIPv4(preferringHost tvHost: String) -> String? {
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }
        var candidates: [String] = []
        var cursor: UnsafeMutablePointer<ifaddrs>? = first
        while let ptr = cursor {
            let flags = Int32(ptr.pointee.ifa_flags)
            let sa = ptr.pointee.ifa_addr.pointee
            if (flags & IFF_UP) != 0, (flags & IFF_LOOPBACK) == 0, sa.sa_family == UInt8(AF_INET) {
                var hostname = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(ptr.pointee.ifa_addr, socklen_t(sa.sa_len), &hostname, socklen_t(hostname.count), nil, 0, NI_NUMERICHOST)
                let ip = String(cString: hostname)
                if ip.hasPrefix("192.168.") || ip.hasPrefix("10.") || ip.hasPrefix("172.") {
                    candidates.append(ip)
                }
            }
            cursor = ptr.pointee.ifa_next
        }
        if let match = candidates.first(where: { Self.sameSubnet($0, tvHost) }) {
            return match
        }
        return candidates.first
    }

    private static func sameSubnet(_ a: String, _ b: String) -> Bool {
        let ap = a.split(separator: ".")
        let bp = b.split(separator: ".")
        guard ap.count == 4, bp.count == 4 else { return false }
        return ap[0] == bp[0] && ap[1] == bp[1] && ap[2] == bp[2]
    }
}
