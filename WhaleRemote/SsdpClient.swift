import Foundation
import Darwin

/// DLNA device seen on the LAN (after SSDP + descriptor XML parse).
struct TvDevice: Identifiable, Hashable {
    let id: String
    let name: String
    let host: String
    let locationURL: URL
    var avTransportControlURL: URL?
    /// Real volume / mute (RenderingControl). Not required for key presses.
    var renderingControlURL: URL?
    var manufacturer: String
}

/// UPnP/SSDP search, same multicast handshake the official Whale TV app uses:
/// `239.255.255.250:1900` with `ST: urn:schemas-upnp-org:device:MediaRenderer:1`
/// plus an `ssdp:all` fallback for stricter firmware.
enum SsdpClient {
    private static let multicastHost = "239.255.255.250"
    private static let multicastPort: UInt16 = 1900

    private static let searchRenderer = """
    M-SEARCH * HTTP/1.1\r
    HOST: 239.255.255.250:1900\r
    MAN: "ssdp:discover"\r
    MX: 3\r
    ST: urn:schemas-upnp-org:device:MediaRenderer:1\r
    \r

    """

    private static let searchAll = """
    M-SEARCH * HTTP/1.1\r
    HOST: 239.255.255.250:1900\r
    MAN: "ssdp:discover"\r
    MX: 3\r
    ST: ssdp:all\r
    \r

    """

    /// Fires M-SEARCH, collects unique LOCATIONs, and downloads each descriptor.
    /// 6 s by default: the Whale firmware sometimes drops the first M-SEARCH.
    static func search(timeout: TimeInterval = 6) async -> [TvDevice] {
        let packets = await withCheckedContinuation { (cont: CheckedContinuation<[String], Never>) in
            DispatchQueue.global(qos: .userInitiated).async {
                cont.resume(returning: receiveResponses(timeout: timeout))
            }
        }

        // 1. Deduplicate SSDP LOCATIONs (one device announces many services).
        var stubs: [TvDevice] = []
        var seenLocation = Set<String>()
        for raw in packets {
            guard let stub = parseSsdp(raw) else { continue }
            if seenLocation.insert(stub.locationURL.absoluteString).inserted {
                stubs.append(stub)
            }
        }

        // 2. Fetch the descriptor for each LOCATION and resolve control URLs.
        //    IMPORTANT: respect the port announced by SSDP; the Whale firmware
        //    rotates that port (observed: 2026, 1566…) so hardcoding breaks
        //    the app whenever the TV reboots.
        var fetched: [TvDevice] = []
        for stub in stubs {
            if let d = await parseDescriptor(at: stub.locationURL, stub: stub) {
                fetched.append(d)
            } else {
                fetched.append(stub)
            }
        }

        // 3. Group by host: the TV publishes two renderers, the real one and
        //    a decoy on port 1393. For each host we pick the first candidate
        //    that:
        //      - has AVTransport resolved,
        //      - is NOT on port 1393 (that one answers 200 but silently drops keys).
        //    Skip hosts that only advertised the decoy or lack AVTransport.
        let groups = Dictionary(grouping: fetched, by: { $0.host })
        var picked: [TvDevice] = []
        for (_, group) in groups {
            if let real = group.first(where: { isRealRenderer($0) }) {
                picked.append(real)
            }
        }
        return picked.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// True when the device looks like the real renderer:
    /// it has AVTransport and is not sitting on the 1393 decoy port.
    private static func isRealRenderer(_ device: TvDevice) -> Bool {
        guard device.avTransportControlURL != nil else { return false }
        let port = device.locationURL.port ?? (device.locationURL.scheme == "https" ? 443 : 80)
        return port != 1393
    }

    private static func receiveResponses(timeout: TimeInterval) -> [String] {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return [] }
        defer { close(fd) }

        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))
        setsockopt(fd, SOL_SOCKET, SO_REUSEPORT, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = 0
        addr.sin_addr = in_addr(s_addr: INADDR_ANY.bigEndian)

        let bindOk: Int32 = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard bindOk == 0 else { return [] }

        var tv = timeval(tv_sec: 0, tv_usec: 400_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        let payloads = [searchRenderer, searchAll]
        for _ in 0..<3 {
            for text in payloads {
                sendMulticast(fd: fd, message: text)
            }
            usleep(300_000)
        }

        var collected: [String] = []
        let deadline = Date().addingTimeInterval(timeout)
        var buffer = [UInt8](repeating: 0, count: 4096)
        while Date() < deadline {
            let n = recv(fd, &buffer, buffer.count, 0)
            if n > 0 {
                collected.append(String(decoding: buffer[0..<n], as: UTF8.self))
            }
        }
        return collected
    }

    private static func sendMulticast(fd: Int32, message: String) {
        var dest = sockaddr_in()
        dest.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        dest.sin_family = sa_family_t(AF_INET)
        dest.sin_port = multicastPort.bigEndian
        inet_pton(AF_INET, multicastHost, &dest.sin_addr)

        message.withCString { cstr in
            let len = strlen(cstr)
            _ = withUnsafePointer(to: &dest) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(fd, cstr, len, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
    }

    private static func parseSsdp(_ response: String) -> TvDevice? {
        let upper = response.uppercased()
        guard upper.contains("200 OK") || upper.contains("NOTIFY") else { return nil }
        var headers: [String: String] = [:]
        for line in response.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            let key = parts[0].trimmingCharacters(in: .whitespaces).lowercased()
            let value = parts[1].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }
        guard let loc = headers["location"], let url = URL(string: loc) else { return nil }
        let usn = headers["usn"] ?? url.host ?? loc
        let id = usn.components(separatedBy: "::").first ?? usn
        let host = url.host ?? "unknown"
        return TvDevice(
            id: id,
            name: host,
            host: host,
            locationURL: url,
            avTransportControlURL: nil,
            renderingControlURL: nil,
            manufacturer: headers["server"] ?? ""
        )
    }

    /// Fetches the UPnP device descriptor for one host:port combination.
    ///
    /// Trap of the Whale TV / Zeasn firmware:
    ///   - It publishes two "MediaRenderer" entries with the same UDN on two
    ///     different ports. The 1393 one answers HTTP 200 to everything and
    ///     silently drops key commands. The other (2026, 1566, …) is the real
    ///     renderer that executes arrows, OK, Home, color buttons, volume.
    ///   - The real port ROTATES on every TV reboot, so it's never hardcoded.
    ///     SSDP announces it; grouping and selection happens in `search()`.
    private static func parseDescriptor(at url: URL, stub: TvDevice) async -> TvDevice? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 2
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return nil }
            return try parseDescriptor(data, stub: stub)
        } catch {
            return nil
        }
    }

    static func parseDescriptor(_ data: Data, stub: TvDevice) throws -> TvDevice {
        let url = stub.locationURL
        let doc = try XMLDocument(data: data, options: .nodeLoadExternalEntitiesNever)
        func value(_ tag: String) throws -> String? {
            try doc.nodes(forXPath: "//*[local-name()='\(tag)']").first?.stringValue?
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        let name = try value("friendlyName") ?? stub.name
        let maker = try value("manufacturer") ?? stub.manufacturer
        let base = resolveBaseURL(advertised: try value("URLBase"), location: url)
        func controlURL(_ service: String) throws -> URL? {
            let type = "urn:schemas-upnp-org:service:\(service):1"
            let query = "//*[local-name()='service'][*[local-name()='serviceType' and normalize-space(.)='\(type)']]/*[local-name()='controlURL']"
            guard let path = try doc.nodes(forXPath: query).first?.stringValue else { return nil }
            return resolve(base: base, path: path.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let av = try controlURL("AVTransport")
        let rc = try controlURL("RenderingControl")
        return TvDevice(
            id: stub.id,
            name: name,
            host: stub.host,
            locationURL: url,
            avTransportControlURL: av,
            renderingControlURL: rc,
            manufacturer: maker
        )
    }

    /// Same rule as the Whale TV app: XML `URLBase` if present, else the directory
    /// portion of the LOCATION URL.
    private static func resolveBaseURL(advertised: String?, location: URL) -> URL {
        if let urlBase = advertised, let url = URL(string: urlBase), url.host != nil {
            return url
        }
        var comps = URLComponents(url: location, resolvingAgainstBaseURL: false)
        comps?.query = nil
        comps?.fragment = nil
        if var path = comps?.path, path.contains("/") {
            if let slash = path.lastIndex(of: "/") {
                path = String(path[..<slash])
                comps?.path = path.isEmpty ? "/" : path
            }
        }
        return comps?.url ?? location
    }

    private static func resolve(base: URL, path: String) -> URL? {
        if path.lowercased().hasPrefix("http://") || path.lowercased().hasPrefix("https://") {
            return URL(string: path)
        }
        // Whale TV concatenation rule: trim trailing slash from base + leading-slash path.
        let trimmed = base.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let suffix = path.hasPrefix("/") ? path : "/" + path
        return URL(string: trimmed + suffix)
    }
}
