import SwiftUI
import AppKit

/// Main window. Two big states:
///   - Not connected: discovery screen with device cards.
///   - Connected: the remote pad itself, with press feedback and an inline spinner.
struct ContentView: View {
    @StateObject private var model = RemoteViewModel()
    /// Text sent to the TV via `setString` + Enter.
    @State private var textToSend: String = ""
    @State private var showTrackpad: Bool = false

    var body: some View {
        ZStack(alignment: .top) {
            // Subtle gradient background for depth; adapts to light/dark mode.
            background
            VStack(spacing: 18) {
                topBar
                if model.isConnected {
                    remotePad
                        .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    discoveryView
                        .transition(.opacity)
                }
                Spacer(minLength: 0)
                footer
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .padding(.bottom, 10)
            // Thin progress strip at the top edge while any HTTP is in flight.
            loadingBar
        }
        .frame(minWidth: 380, minHeight: 640)
        .animation(.easeInOut(duration: 0.25), value: model.isConnected)
    }

    // MARK: - Chrome

    private var background: some View {
        LinearGradient(
            colors: [
                Color(nsColor: .windowBackgroundColor),
                Color(nsColor: .underPageBackgroundColor)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
        .ignoresSafeArea()
    }

    /// Top bar: TV name + connection chip + quick actions.
    private var topBar: some View {
        HStack(spacing: 12) {
            Image(systemName: "tv")
                .font(.title2)
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.selected?.name ?? "Whale Remote")
                    .font(.headline)
                    .lineLimit(1)
                Text(statusLine)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            // Native circular spinner while a request is in flight. AppKit paints
            // this at the display refresh rate, so it can never stutter.
            if model.inFlight > 0 {
                ProgressView()
                    .controlSize(.small)
                    .transition(.opacity)
            }
            if model.isConnected {
                Button(role: .destructive) {
                    model.disconnect()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .font(.title3)
                }
                .buttonStyle(.plain)
                .help("Disconnect")
            }
        }
        .animation(.easeInOut(duration: 0.15), value: model.inFlight > 0)
    }

    private var statusLine: String {
        if model.isConnected {
            if let host = model.selected?.host {
                return "Connected · \(host)"
            }
            return "Connected"
        }
        if model.isSearching { return "Searching the Wi‑Fi…" }
        return "Tap Search TVs to start"
    }

    /// Thin bar at the top edge while an HTTP request is in flight.
    ///
    /// Uses `TimelineView(.animation)` so SwiftUI advances the offset on every
    /// display refresh. An earlier attempt computed the offset from `Date()`
    /// inside the body, which only moved when something else triggered a
    /// re-render — hence the stutter.
    @ViewBuilder private var loadingBar: some View {
        if model.inFlight > 0 {
            TimelineView(.animation(minimumInterval: 1.0 / 60.0)) { context in
                GeometryReader { geo in
                    let period: Double = 1.2 // seconds per cycle
                    let t = context.date.timeIntervalSinceReferenceDate
                        .truncatingRemainder(dividingBy: period) / period
                    let barWidth = geo.size.width * 0.35
                    let travel = geo.size.width + barWidth
                    let x = CGFloat(t) * travel - barWidth
                    LinearGradient(
                        colors: [Color.accentColor.opacity(0), Color.accentColor, Color.accentColor.opacity(0)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: barWidth, height: 2)
                    .offset(x: x)
                }
            }
            .frame(height: 2)
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.15), value: model.inFlight > 0)
        }
    }

    /// Footer: build version + last key sent. Useful to tell which DMG is open
    /// in case Finder keeps older copies in /Applications.
    private var footer: some View {
        HStack(spacing: 10) {
            Text(AppVersion.footer)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
            Spacer()
            if let key = model.lastKey {
                Text(key)
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    // MARK: - Discovery

    private var discoveryView: some View {
        VStack(spacing: 14) {
            Button {
                Task { await model.search() }
            } label: {
                HStack(spacing: 8) {
                    if model.isSearching {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                    }
                    Text(model.isSearching ? "Searching…" : "Search TVs")
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.isSearching)
            .keyboardShortcut("r", modifiers: [.command])

            if model.devices.isEmpty && !model.isSearching {
                emptyDiscoveryHint
            } else {
                VStack(spacing: 10) {
                    ForEach(model.devices) { device in
                        deviceCard(device)
                    }
                }
            }
            if let err = model.lastError {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var emptyDiscoveryHint: some View {
        VStack(spacing: 6) {
            Image(systemName: "wifi")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("Make sure the Mac and the TV are on the same Wi‑Fi network.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    /// Card shown for each discovered TV. Click to connect.
    private func deviceCard(_ device: TvDevice) -> some View {
        Button {
            Task { await model.connect(device) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "tv")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(device.name).font(.headline)
                    Text(device.host).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(device.avTransportControlURL == nil)
    }

    // MARK: - Remote pad

    /// The remote itself: D-pad, navigation row, volume, text input, colors,
    /// optional trackpad, power.
    private var remotePad: some View {
        VStack(spacing: 20) {
            dpad
            navRow
            volumeRow
            textInput
            colorRow
            trackpadToggle
            if showTrackpad { trackpad }
            powerButton
        }
    }

    // MARK: - D-pad

    /// Round D-pad with a large OK in the middle. It's the hero element.
    private var dpad: some View {
        ZStack {
            Circle()
                .fill(Color(nsColor: .controlBackgroundColor))
                .overlay(
                    Circle().stroke(Color(nsColor: .separatorColor), lineWidth: 1)
                )
                .frame(width: 220, height: 220)
            VStack(spacing: 0) {
                arrowButton(.up)
                HStack(spacing: 0) {
                    arrowButton(.left)
                    okButton
                    arrowButton(.right)
                }
                arrowButton(.down)
            }
        }
        .padding(.vertical, 6)
    }

    private enum Arrow { case up, down, left, right }
    private func arrowButton(_ arrow: Arrow) -> some View {
        let (symbol, keyCode): (String, String) = {
            switch arrow {
            case .up:    return ("chevron.up", RemoteKeys.up)
            case .down:  return ("chevron.down", RemoteKeys.down)
            case .left:  return ("chevron.left", RemoteKeys.left)
            case .right: return ("chevron.right", RemoteKeys.right)
            }
        }()
        return Button {
            model.press(keyCode)
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 22, weight: .semibold))
                .frame(width: 60, height: 60)
                .contentShape(Rectangle())
        }
        .buttonStyle(PressFeedbackButtonStyle())
    }

    private var okButton: some View {
        Button {
            model.press(RemoteKeys.ok)
        } label: {
            Text("OK")
                .font(.headline)
                .foregroundStyle(.white)
                .frame(width: 70, height: 70)
                .background(
                    Circle().fill(Color.accentColor)
                )
                .contentShape(Circle())
        }
        .buttonStyle(PressFeedbackButtonStyle(scale: 0.88))
    }

    // MARK: - Secondary rows

    private var navRow: some View {
        HStack(spacing: 10) {
            iconButton("chevron.backward", label: "Back") { model.press(RemoteKeys.back) }
            iconButton("house.fill", label: "Home") { model.press(RemoteKeys.home) }
            iconButton("gearshape.fill", label: "Settings") { model.press(RemoteKeys.settings) }
            iconButton("rectangle.on.rectangle", label: "Input") { model.press(RemoteKeys.source) }
        }
    }

    private var volumeRow: some View {
        HStack(spacing: 10) {
            iconButton("speaker.wave.1.fill", label: "Vol −") { model.press(RemoteKeys.volumeDown) }
            iconButton("speaker.slash.fill", label: "Mute") { model.press(RemoteKeys.mute) }
            iconButton("speaker.wave.3.fill", label: "Vol +") { model.press(RemoteKeys.volumeUp) }
        }
    }

    private var powerButton: some View {
        Button {
            model.press(RemoteKeys.power)
        } label: {
            Image(systemName: "power")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.red.opacity(0.85)))
        }
        .buttonStyle(PressFeedbackButtonStyle(scale: 0.86))
        .help("Power on / off")
        .padding(.top, 4)
    }

    /// Text input pill. Sends the string + automatic Enter, the way the
    /// official app does after typing.
    private var textInput: some View {
        HStack(spacing: 8) {
            Image(systemName: "keyboard")
                .foregroundStyle(.secondary)
            TextField("Type to send to the TV…", text: $textToSend, onCommit: sendCurrentText)
                .textFieldStyle(.plain)
            if !textToSend.isEmpty {
                Button {
                    sendCurrentText()
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
        )
    }

    private func sendCurrentText() {
        guard !textToSend.isEmpty else { return }
        model.sendText(textToSend)
        textToSend = ""
    }

    /// Row with the four color buttons from the remote. On Whale projectors
    /// each color triggers a different image adjustment baked into the firmware
    /// (you discover which one by pressing them).
    private var colorRow: some View {
        HStack(spacing: 14) {
            colorDot(.red) { model.press(RemoteKeys.colorRed) }
            colorDot(.green) { model.press(RemoteKeys.colorGreen) }
            colorDot(.yellow) { model.press(RemoteKeys.colorYellow) }
            colorDot(.blue) { model.press(RemoteKeys.colorBlue) }
        }
    }

    private func colorDot(_ color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(color)
                .frame(width: 30, height: 30)
                .overlay(Circle().stroke(Color.white.opacity(0.18), lineWidth: 1))
                .shadow(color: color.opacity(0.35), radius: 4, y: 1)
        }
        .buttonStyle(PressFeedbackButtonStyle(scale: 0.82))
    }

    /// Toggle to show or hide the trackpad (it takes a good chunk of space).
    private var trackpadToggle: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { showTrackpad.toggle() }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: showTrackpad ? "chevron.down" : "chevron.up")
                Text(showTrackpad ? "Hide trackpad" : "Show trackpad")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    private var trackpad: some View {
        TrackpadView(
            onMove: { dx, dy in model.move(x: dx, y: dy) },
            onClick: { model.press(RemoteKeys.mouseLeft) }
        )
        .frame(height: 130)
        .overlay(
            Text("Trackpad · drag / click")
                .font(.caption)
                .foregroundStyle(.secondary)
        )
    }

    // MARK: - Shared icon button

    /// Square pill with icon + short label. Used for every secondary control.
    private func iconButton(_ system: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: system)
                    .font(.system(size: 18, weight: .semibold))
                Text(label)
                    .font(.caption2)
            }
            .frame(maxWidth: .infinity, minHeight: 54)
            .padding(.horizontal, 2)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
            )
        }
        .buttonStyle(PressFeedbackButtonStyle())
    }
}

/// Button style that gives immediate press feedback: a small scale-down and a
/// subtle brightness dip. Makes the remote feel responsive even when the HTTP
/// round-trip takes a few milliseconds.
struct PressFeedbackButtonStyle: ButtonStyle {
    var scale: CGFloat = 0.94

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1.0)
            .brightness(configuration.isPressed ? -0.05 : 0)
            .animation(.spring(response: 0.18, dampingFraction: 0.55), value: configuration.isPressed)
    }
}

/// Optional trackpad (TR_MOVE + left click).
private struct TrackpadView: NSViewRepresentable {
    var onMove: (Int, Int) -> Void
    var onClick: () -> Void

    func makeNSView(context: Context) -> NSView {
        let view = PadView()
        view.onMove = onMove
        view.onClick = onClick
        view.wantsLayer = true
        view.layer?.cornerRadius = 12
        view.layer?.backgroundColor = NSColor.controlBackgroundColor.withAlphaComponent(0.6).cgColor
        view.layer?.borderColor = NSColor.separatorColor.cgColor
        view.layer?.borderWidth = 1
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}

    final class PadView: NSView {
        var onMove: ((Int, Int) -> Void)?
        var onClick: (() -> Void)?
        private var last: NSPoint?
        private var dragOccurred = false

        override func mouseDragged(with event: NSEvent) {
            let p = convert(event.locationInWindow, from: nil)
            var didDrag = false
            if let last {
                let dx = Int((p.x - last.x).rounded())
                let dy = Int((last.y - p.y).rounded())
                if dx != 0 || dy != 0 {
                    didDrag = true
                    onMove?(dx, dy)
                }
            }
            last = p
            if didDrag { dragOccurred = true }
        }
        override func mouseDown(with event: NSEvent) {
            dragOccurred = false
            last = convert(event.locationInWindow, from: nil)
        }
        override func mouseUp(with event: NSEvent) {
            if !dragOccurred { onClick?() }
            last = nil
            dragOccurred = false
        }
    }
}
