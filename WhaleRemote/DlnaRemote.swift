import Foundation

/// DLNA client that talks to the Whale/ZEASN TV.
///
/// Two independent control surfaces are used:
///
///   - `RenderingControl` → real volume and mute (`SetVolume`, `SetMute`).
///     The firmware honors these.
///   - `AVTransport` + `Seek` with a custom XML `setKey` payload → navigation
///     keys, OK, Home, color buttons, text input. This is the Zeasn extension
///     the official Whale TV app uses.
actor DlnaRemote {
    let controlURL: URL
    let renderingURL: URL?

    init(controlURL: URL, renderingURL: URL?) {
        self.controlURL = controlURL
        self.renderingURL = renderingURL
    }

    func sendKey(_ keyCode: String) async throws -> String {
        try await seekAV(target: commandXML(name: "setKey", keyCode: keyCode), label: "setKey \(keyCode)")
    }

    /// Sends a string of text to the TV's focused input (search bar, login, …).
    /// Mirrors `DlnaController.sendString` in the APK: action `setString`, the
    /// string travels as the `keyCode` attribute. The TV pipes it into the field.
    func sendString(_ text: String) async throws -> String {
        try await seekAV(target: commandXML(name: "setString", keyCode: text), label: "setString \(text.count) chars")
    }

    func sendHeartbeat(localIP: String) async throws -> String {
        try await seekAV(
            target: commandXML(name: "setHeartbeat", keyCode: "COMMAND_HEARTBEAT=\(localIP)"),
            label: "heartbeat \(localIP)"
        )
    }

    func volumeUp() async throws -> String {
        try await bumpVolume(+5)
    }

    func volumeDown() async throws -> String {
        try await bumpVolume(-5)
    }

    func toggleMute() async throws -> String {
        guard let renderingURL else { throw RemoteError.noControlURL }
        let muted = (try await extractTag(soap(
            url: renderingURL,
            service: "urn:schemas-upnp-org:service:RenderingControl:1",
            action: "GetMute",
            params: "<InstanceID>0</InstanceID><Channel>Master</Channel>"
        ), tag: "CurrentMute") ?? "0") != "0"
        let next = muted ? "0" : "1"
        _ = try await soap(
            url: renderingURL,
            service: "urn:schemas-upnp-org:service:RenderingControl:1",
            action: "SetMute",
            params: "<InstanceID>0</InstanceID><Channel>Master</Channel><DesiredMute>\(next)</DesiredMute>"
        )
        return "mute → \(next == "1" ? "ON" : "OFF")"
    }

    private func bumpVolume(_ delta: Int) async throws -> String {
        guard let renderingURL else { throw RemoteError.noControlURL }
        let raw = try await extractTag(soap(
            url: renderingURL,
            service: "urn:schemas-upnp-org:service:RenderingControl:1",
            action: "GetVolume",
            params: "<InstanceID>0</InstanceID><Channel>Master</Channel>"
        ), tag: "CurrentVolume") ?? "0"
        let current = Int(raw) ?? 0
        let next = min(100, max(0, current + delta))
        _ = try await soap(
            url: renderingURL,
            service: "urn:schemas-upnp-org:service:RenderingControl:1",
            action: "SetVolume",
            params: "<InstanceID>0</InstanceID><Channel>Master</Channel><DesiredVolume>\(next)</DesiredVolume>"
        )
        return "volume \(current) → \(next)"
    }

    func sendMouseMove(x: Int, y: Int, isScroll: Bool = false) async throws -> String {
        let xml = "<?xml version=\"1.0\" encoding=\"utf-8\"?><root><action name=\"setEventMoveAction\" eventAction=\"TR_MOVE\" x=\"\(x)\" y=\"\(y)\" isScroll=\"\(isScroll ? "true" : "false")\" /></root>"
        return try await seekAV(target: xml, label: "TR_MOVE \(x),\(y)")
    }

    private func commandXML(name: String, keyCode: String) -> String {
        "<?xml version=\"1.0\" encoding=\"utf-8\"?><root><action name=\"\(name)\" eventAction=\"TR_PRESS\" keyCode=\"\(keyCode)\" /></root>"
    }

    /// Envelope identical to `DlnaController.kt` from the APK (params concatenated).
    private func seekAV(target: String, label: String) async throws -> String {
        let escaped = escape(target)
        let body = try await soap(
            url: controlURL,
            service: "urn:schemas-upnp-org:service:AVTransport:1",
            action: "Seek",
            params: "<InstanceID>0</InstanceID><Unit>REL_TIME</Unit><Target>\(escaped)</Target>"
        )
        return "\(label) HTTP 200 (\(body.count) bytes)"
    }

    @discardableResult
    private func soap(url: URL, service: String, action: String, params: String) async throws -> String {
        let envelope = "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
            + "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\">\n"
            + "  <s:Body>\n"
            + "    <u:\(action) xmlns:u=\"\(service)\">\n"
            + "      \(params)\n"
            + "    </u:\(action)>\n"
            + "  </s:Body>\n"
            + "</s:Envelope>"
        let data = Data(envelope.utf8)
        let response = try await UpnpHttp.post(
            url: url,
            headers: [
                "Content-Type": "text/xml; charset=\"utf-8\"",
                "SOAPAction": "\"\(service)#\(action)\"",
            ],
            body: data
        )
        if !(200...299).contains(response.status) {
            throw RemoteError.http(response.status, response.body)
        }
        if response.body.localizedCaseInsensitiveContains("UPnPError") {
            throw RemoteError.soapFault(response.body)
        }
        return response.body
    }

    private func extractTag(_ xml: String, tag: String) -> String? {
        guard let start = xml.range(of: "<\(tag)>"),
              let end = xml.range(of: "</\(tag)>", range: start.upperBound..<xml.endIndex) else { return nil }
        return String(xml[start.upperBound..<end.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func escape(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }
}

enum RemoteError: LocalizedError {
    case http(Int, String)
    case soapFault(String)
    case noControlURL
    case badURL
    case socket(String)

    var errorDescription: String? {
        switch self {
        case .http(let code, let log): return "HTTP \(code). \(log)"
        case .soapFault(let log): return "SOAP Fault. \(log)"
        case .noControlURL: return "This device does not expose the required DLNA service"
        case .badURL: return "Invalid control URL"
        case .socket(let msg): return "Network: \(msg)"
        }
    }
}
