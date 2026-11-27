import Foundation

private actor TestTV {
    var volume = 20
    var texts: [String] = []
    var keys: [String] = []
    var rejectHeartbeat = false
    func goOffline() { rejectHeartbeat = true }

    func post(_ url: URL, _ headers: [String: String], _ data: Data) async throws -> UpnpHttp.Response {
        let doc = try XMLDocument(data: data)
        func value(_ name: String) throws -> String {
            try doc.nodes(forXPath: "//*[local-name()='\(name)']").first!.stringValue!
        }
        var body = "<ok/>"
        switch headers["SOAPAction"]! {
        case let action where action.contains("#GetVolume"):
            body = "<CurrentVolume>\(volume)</CurrentVolume>"
            try await Task.sleep(nanoseconds: 10_000_000)
        case let action where action.contains("#SetVolume"):
            volume = try Int(value("DesiredVolume"))!
        default:
            let inner = try XMLDocument(xmlString: value("Target"))
            let action = try inner.nodes(forXPath: "/root/action").first as! XMLElement
            let code = action.attribute(forName: "keyCode")!.stringValue!
            switch action.attribute(forName: "name")!.stringValue! {
            case "setString": texts.append(code)
            case "setKey": keys.append(code)
            case "setHeartbeat" where rejectHeartbeat: throw URLError(.timedOut)
            default: break
            }
        }
        return .init(status: 200, body: body)
    }
}

@main struct RemoteTests {
    @MainActor static func wait(_ condition: () async -> Bool) async throws {
        for _ in 0..<500 {
            if await condition() { return }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        fatalError("Timed out waiting for test state")
    }

    @MainActor static func main() async throws {
        let url = URL(string: "http://192.0.2.1/control")!
        let device = TvDevice(id: "test", name: "Test TV", host: "192.0.2.1", locationURL: url,
                              avTransportControlURL: url, renderingControlURL: url, manufacturer: "Test")
        let xml = """
        <root xmlns="urn:schemas-upnp-org:device-1-0"><device>
        <friendlyName>Kitchen &amp; Dining</friendlyName><serviceList><service>
        <serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
        <controlURL>/av</controlURL></service></serviceList></device></root>
        """
        let parsed = try SsdpClient.parseDescriptor(Data(xml.utf8), stub: device)
        precondition(parsed.name == "Kitchen & Dining" && parsed.avTransportControlURL?.path == "/av")
        precondition(parsed.renderingControlURL == nil)
        let tv = TestTV()
        let model = RemoteViewModel(discover: { [device] }, makeRemote: {
            DlnaRemote(controlURL: $0, renderingURL: $1, post: tv.post)
        })
        await model.search()
        precondition(model.devices == [device])
        await model.connect(device)
        try await wait { model.isConnected }

        let sample = "Tom & Jerry <\"café\"> 🐋"
        model.sendText(sample)
        model.press(RemoteKeys.volumeUp)
        model.press(RemoteKeys.volumeUp)
        try await wait { model.inFlight == 0 }
        let (volume, texts, keys) = await (tv.volume, tv.texts, tv.keys)
        precondition(volume == 30 && texts == [sample] && keys == [RemoteKeys.enter])
        let client = DlnaRemote(controlURL: url, renderingURL: url, post: tv.post)
        async let first = client.volumeDown()
        async let second = client.volumeDown()
        _ = try await (first, second)
        let finalVolume = await tv.volume
        precondition(finalVolume == 20)
        model.sendText(sample, pressEnter: false)
        try await wait { model.inFlight == 0 }
        precondition(model.lastKey?.contains(sample) == false)

        model.sendText("old session")
        model.press(RemoteKeys.power)
        try await wait { await tv.texts.last == "old session" }
        model.disconnect()
        await tv.goOffline()
        await model.connect(device)
        try await wait { model.connection == .failed }
        try await Task.sleep(nanoseconds: 200_000_000)
        let finalKeys = await tv.keys
        precondition(finalKeys == keys && model.lastError != nil && model.inFlight == 0)
        print("Passed discovery, connection, text, volume ordering and session cancellation.")
    }
}
