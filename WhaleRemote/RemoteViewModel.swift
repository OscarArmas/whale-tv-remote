import Foundation
import Darwin

@MainActor
final class RemoteViewModel: ObservableObject {
    @Published var devices: [TvDevice] = []
    @Published var isSearching = false
    @Published var status = "Tap Search TVs to start"
    @Published var selected: TvDevice?
    @Published var lastError: String?
    @Published var lastLog: String?
    @Published var lastKey: String?
    /// Number of HTTP requests in flight. The UI uses this to show the spinner
    /// and the top loading bar while anything is being sent.
    @Published var inFlight: Int = 0

    private var remote: DlnaRemote?
    private var heartbeatTask: Task<Void, Never>?
    private var localIP = "0.0.0.0"

    /// Starts counting one in-flight request (drives the UI spinner).
    private func startInFlight() { inFlight += 1 }
    private func endInFlight() { if inFlight > 0 { inFlight -= 1 } }

    var isConnected: Bool { remote != nil && selected != nil }

    func search() async {
        isSearching = true
        status = "Looking for MediaRenderer devices on the network…"
        lastError = nil
        let found = await SsdpClient.search()
        devices = found
        status = found.isEmpty
            ? "Nothing found. Make sure the Mac is on the same Wi‑Fi as the TV."
            : "\(found.count) device(s) found. Pick one and connect."
        isSearching = false
    }

    func connect(_ device: TvDevice) async {
        guard let url = device.avTransportControlURL else {
            lastError = RemoteError.noControlURL.localizedDescription
            return
        }
        disconnect()
        selected = device
        let client = DlnaRemote(controlURL: url, renderingURL: device.renderingControlURL)
        remote = client
        localIP = Self.guessLocalIPv4(preferringHost: device.host) ?? "0.0.0.0"
        // The real remote-control port rotates (we've seen 2026 and 1566); show it
        // so we can tell at a glance whether SSDP picked the right one.
        let portHint = "channel: \(url.host ?? "?"):\(url.port.map(String.init) ?? "80")"
        status = "Connected to \(device.name)\n\(portHint)"
        lastError = nil
        lastLog = portHint
        lastKey = nil
        Task {
            do {
                lastLog = try await client.sendHeartbeat(localIP: localIP)
            } catch {
                lastError = error.localizedDescription
            }
        }
        startHeartbeat()
    }

    func disconnect() {
        heartbeatTask?.cancel()
        heartbeatTask = nil
        remote = nil
        selected = nil
        status = "Disconnected"
    }

    func press(_ key: String) {
        guard let remote else { return }
        lastKey = key
        startInFlight()
        Task {
            defer { Task { @MainActor in self.endInFlight() } }
            do {
                switch key {
                case RemoteKeys.volumeUp:
                    lastLog = try await remote.volumeUp()
                case RemoteKeys.volumeDown:
                    lastLog = try await remote.volumeDown()
                case RemoteKeys.mute:
                    lastLog = try await remote.toggleMute()
                default:
                    lastLog = try await remote.sendKey(key)
                }
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    /// Sends a text string to the TV's focused input (search bars, logins, etc.).
    /// Uses the Zeasn `setString` action. When `pressEnter` is true, immediately
    /// follows up with TR_KEY_ENTER — this is what the official app does.
    func sendText(_ text: String, pressEnter: Bool = true) {
        guard let remote, !text.isEmpty else { return }
        lastKey = "txt:\(text)"
        startInFlight()
        Task {
            defer { Task { @MainActor in self.endInFlight() } }
            do {
                lastLog = try await remote.sendString(text)
                if pressEnter {
                    // Give the TV a beat to apply the text before confirming it.
                    try? await Task.sleep(nanoseconds: 150_000_000)
                    _ = try await remote.sendKey(RemoteKeys.enter)
                }
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    func move(x: Int, y: Int) {
        guard let remote else { return }
        // The trackpad fires many events per second; skip the in-flight counter
        // for these so the spinner does not blink constantly.
        Task {
            do {
                lastLog = try await remote.sendMouseMove(x: x, y: y)
                lastError = nil
            } catch {
                lastError = error.localizedDescription
            }
        }
    }

    private func startHeartbeat() {
        heartbeatTask?.cancel()
        let ip = localIP
        heartbeatTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 10_000_000_000)
                guard let self, let remote = self.remote else { return }
                do {
                    _ = try await remote.sendHeartbeat(localIP: ip)
                } catch {
                    await MainActor.run { self.lastError = "Heartbeat: \(error.localizedDescription)" }
                }
            }
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
