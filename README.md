# Whale Remote (macOS)

A tiny, dependency-free macOS remote for Whale TV / ZEASN projectors and
televisions. No cloud, no account, no telemetry — pure LAN control over the
same DLNA/SOAP protocol the official Whale TV app uses.

Why it exists: the official Android/iOS app works fine, but there is no macOS
build. This project reverse-engineers the exact packets the official app
sends and reproduces them from a native SwiftUI window.

## Features

- **Discovery** via UPnP/SSDP (no manual IP).
- **D-pad, OK, Back, Home, Settings, Input source**.
- **Volume ± and Mute** via `RenderingControl` (real system volume).
- **Color buttons (R/G/Y/B)** for projector image adjustments.
- **Text input** via the `setString` action + automatic Enter.
- **Trackpad** (optional) with mouse-move + click.
- **Keep-alive HTTP** so consecutive presses feel instant.
- **Animated loading indicator** driven by `TimelineView(.animation)` for
  smooth 60 Hz feedback.

## Requirements

- macOS 13 Ventura or newer.
- Xcode Command Line Tools:

  ```sh
  xcode-select --install
  ```

- The TV must be on the same Wi-Fi as the Mac.

## Build

```sh
./build.sh
```

Produces an ad-hoc signed `.app` and a `.dmg` under `dist/`.

Open the DMG, drag `Whale Remote` into `/Applications`, launch it, click
**Search TVs**, pick your TV and you're in.

## Project layout

| File | Purpose |
| --- | --- |
| `WhaleRemote/WhaleRemoteApp.swift` | SwiftUI app entry point. |
| `WhaleRemote/ContentView.swift` | UI: discovery screen and remote pad. |
| `WhaleRemote/RemoteViewModel.swift` | Observable state glue between UI and `DlnaRemote`. |
| `WhaleRemote/SsdpClient.swift` | UPnP/SSDP M-SEARCH discovery and descriptor parse. |
| `WhaleRemote/DlnaRemote.swift` | SOAP calls to AVTransport and RenderingControl. |
| `WhaleRemote/UpnpHttp.swift` | `URLSession` wrapper with HTTP/1.1 keep-alive. |
| `WhaleRemote/RemoteKeys.swift` | `TR_KEY_*` constants expected by the firmware. |
| `WhaleRemote/AppVersion.swift` | Version/build string shown in the UI footer. |
| `build.sh` | Compiles with `swiftc`, packages `.app` and `.dmg`. |

## Protocol notes (reverse-engineered)

- Discovery: SSDP `M-SEARCH` on `239.255.255.250:1900`, ST
  `urn:schemas-upnp-org:device:MediaRenderer:1` and `ssdp:all`.
- The TV advertises **two** MediaRenderer endpoints with the same UDN. The
  one on port **1393 is a decoy** that answers HTTP 200 to every request and
  silently drops key commands. The real one lives on a port that **rotates
  on every reboot** (observed: 2026, 1566, …). `SsdpClient` always respects
  the port SSDP advertises and discards the 1393 one.
- Keys travel inside an AVTransport `Seek` request, with the inner XML
  payload XML-escaped as the `Target` field:

  ```xml
  <?xml version="1.0" encoding="utf-8"?>
  <root>
    <action name="setKey" eventAction="TR_PRESS" keyCode="TR_KEY_UP" />
  </root>
  ```

- Volume uses the standard `RenderingControl#SetVolume` with `Channel=Master`.
- Text input uses the same wrapper but with `action name="setString"` and
  the whole string as `keyCode`.
- Heartbeat: every 10 s the same `Seek` wrapper is sent with
  `setHeartbeat COMMAND_HEARTBEAT=<local-ip>`.

## License

Personal project, provided as-is. No warranty. Use on networks you own.
