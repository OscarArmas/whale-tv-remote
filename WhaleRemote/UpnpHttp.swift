import Foundation

/// HTTP client used to talk to the Whale/ZEASN TV.
///
/// Earlier iterations used raw sockets because URLSession sometimes negotiated
/// HTTP/2 and the TV's UPnP stack didn't understand it. On this firmware
/// (DLNADOC/1.50 Zeasn 1.0.5.13) the server replies in HTTP/1.1 and honors
/// `Connection: keep-alive`, so URLSession stays on HTTP/1.1 and also reuses
/// the TCP connection across requests.
///
/// Why URLSession wins here:
///   - Connection pooling: a single TCP handshake serves many key presses in
///     a row. This removed the ~150–300 ms of per-press latency that made the
///     remote feel sluggish.
///   - Native timeouts, cancellation and error handling.
enum UpnpHttp {
    struct Response {
        let status: Int
        let body: String
    }

    /// Single shared `URLSession`. Keeps up to 4 pooled connections per host.
    private static let session: URLSession = {
        let cfg = URLSessionConfiguration.ephemeral
        cfg.httpMaximumConnectionsPerHost = 4
        cfg.httpShouldUsePipelining = false
        cfg.requestCachePolicy = .reloadIgnoringLocalCacheData
        cfg.timeoutIntervalForRequest = 4
        cfg.timeoutIntervalForResource = 6
        // `assumesHTTP3Capable` isn't available on macOS 13; the TV only speaks
        // HTTP/1.1 anyway so URLSession downgrades automatically.
        return URLSession(configuration: cfg)
    }()

    static func get(url: URL, timeout: TimeInterval = 5) async throws -> Response {
        try await perform(method: "GET", url: url, headers: [:], body: nil, timeout: timeout)
    }

    static func post(url: URL, headers: [String: String], body: Data, timeout: TimeInterval = 5) async throws -> Response {
        try await perform(method: "POST", url: url, headers: headers, body: body, timeout: timeout)
    }

    private static func perform(method: String, url: URL, headers: [String: String], body: Data?, timeout: TimeInterval) async throws -> Response {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = timeout
        request.httpBody = body
        // Explicit keep-alive: TV holds the TCP open for the next press.
        request.setValue("keep-alive", forHTTPHeaderField: "Connection")
        // Same User-Agent the official Whale TV app uses (captured via mitmproxy).
        request.setValue("ktor-client", forHTTPHeaderField: "User-Agent")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }
        do {
            let (data, resp) = try await session.data(for: request)
            let status = (resp as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) ?? ""
            return Response(status: status, body: body)
        } catch {
            throw RemoteError.socket(error.localizedDescription)
        }
    }
}
