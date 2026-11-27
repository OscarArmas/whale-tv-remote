# Whale TV Remote for Mac (and iPhone)

**Unofficial remote control app for Whale TV, Whale projectors and any
Zeasn-based smart TV.** Control your TV from your Mac or iPhone over Wi-Fi:
arrows, OK, Home, volume, mute, HDMI source, color buttons, text input and a
virtual trackpad. No account, no cloud, no telemetry — everything happens
on your local network.

> Looking for a "Whale TV app for Mac" because the official one only ships
> for Android and iOS? This is exactly that: a tiny, native, open-source
> replacement for the official Whale TV / Zeasn mobile remote.

![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-blue)

## Why this exists

The official **Whale TV app** (by Zeasn) is only available on Android and
iOS. If you own a Whale TV, Whale projector, or any Android TV powered by
the ZEASN WhaleOS firmware, this project lets you drive it from macOS using
the same protocol the official app uses — reverse-engineered from the
Android APK and verified with live packet captures.

## Compatibility

Tested on:

- **Whale TV / Whale projectors** running WhaleOS (Zeasn 1.x firmware)
- Models with `Zeasn/1.0.5.13` in their UPnP `Server:` header

Should also work on any TV that advertises a `MediaRenderer:1` service with
Zeasn's `remoteControl` extension. It will NOT work on generic DLNA
renderers (Chromecast, Roku, Sony Bravia, etc.) because the key-press
payload is Zeasn-specific.

## Features

- 🔍 **Automatic discovery** via UPnP/SSDP — no need to type an IP.
- ⬆️⬇️⬅️➡️ **Full D-pad + OK**.
- 🏠 Back, Home, Settings (main menu), HDMI input, Power.
- 🔊 Volume up/down and mute (real `RenderingControl#SetVolume`, not a
  key simulation).
- 🔴🟢🟡🔵 Color buttons for projector image adjustments.
- ⌨️ **Text input**: type on your Mac, it goes straight into the TV's
  focused field (YouTube search, Netflix login, etc.) with automatic
  Enter.
- 🖱️ Virtual **trackpad** with sensitivity and move-coalescing so the
  cursor feels snappy over Wi-Fi.
- 🌓 Native SwiftUI UI with light / dark mode.
- 🔌 Keep-alive HTTP so consecutive presses reuse the TCP connection.

## Install

1. Download the latest `WhaleRemote-<version>.dmg` from the
   [Releases](../../releases) page.
2. Open the DMG and drag **Whale Remote** into `/Applications`.
3. The app is ad-hoc signed — the first time you launch it, right-click the
   app and choose **Open** to bypass Gatekeeper.
4. Click **Search TVs**, pick your TV, press keys.

Requires **macOS 13 Ventura** or newer.

## Build from source

Only the Xcode Command Line Tools are needed (no full Xcode required for
the macOS build):

```sh
xcode-select --install
git clone https://github.com/<your-user>/whale-tv-remote.git
cd whale-tv-remote
./build.sh
```

The script produces an ad-hoc signed `.app` and a `.dmg` under `dist/`.

## How it works

- **Discovery**: SSDP `M-SEARCH` on `239.255.255.250:1900` with
  `ST: urn:schemas-upnp-org:device:MediaRenderer:1` and `ssdp:all`.
- **Decoy port handling**: Whale TV publishes **two** MediaRenderer
  entries with the same UDN. The one on port `1393` answers HTTP 200 to
  every request and silently drops key commands. The real one lives on
  a port that **rotates on every reboot** (observed `2026`, `1566`, …).
  `SsdpClient` always respects the port SSDP announces and discards the
  1393 decoy.
- **Key presses** travel inside an AVTransport `Seek` request, with the
  inner XML payload XML-escaped as the `Target` field:

  ```xml
  <?xml version="1.0" encoding="utf-8"?>
  <root>
    <action name="setKey" eventAction="TR_PRESS" keyCode="TR_KEY_UP"/>
  </root>
  ```

- **Volume** uses the standard `RenderingControl#SetVolume`,
  `Channel=Master`.
- **Text input** uses the same wrapper but with
  `action name="setString"` and the whole string as `keyCode`.
- **Heartbeat**: every 10 s the same Seek wrapper is sent with
  `setHeartbeat COMMAND_HEARTBEAT=<local-ip>`.

Full details are inline-documented in `WhaleRemote/DlnaRemote.swift` and
`WhaleRemote/SsdpClient.swift`.

## Project layout

| File | Purpose |
| --- | --- |
| `WhaleRemote/WhaleRemoteApp.swift` | SwiftUI app entry point |
| `WhaleRemote/ContentView.swift` | UI: discovery + remote pad + trackpad |
| `WhaleRemote/RemoteViewModel.swift` | Observable glue, heartbeat, in-flight counter |
| `WhaleRemote/SsdpClient.swift` | SSDP discovery + descriptor parsing |
| `WhaleRemote/DlnaRemote.swift` | SOAP calls for AVTransport + RenderingControl |
| `WhaleRemote/UpnpHttp.swift` | URLSession with HTTP/1.1 keep-alive |
| `WhaleRemote/RemoteKeys.swift` | `TR_KEY_*` constants |
| `WhaleRemote/AppVersion.swift` | Version string in the footer |
| `build.sh` | swiftc + hdiutil pipeline that produces the DMG |

## FAQ

**Does it need the internet?**
No. Everything is LAN-only. Works on Wi-Fi networks with no outbound
connectivity.

**Does it need a Whale TV account?**
No. Zero accounts, zero sign-in, zero telemetry.

**Why does my TV not show up?**
Mac and TV must be on the same Wi-Fi SSID / subnet. Some mesh networks
isolate clients; disable "client isolation" on the AP. Hit **Search TVs**
twice if nothing appears on the first try (UDP SSDP can drop packets).

**Will this control my `<other brand>` TV?**
No. The payload is Whale / Zeasn specific. Generic DLNA, Chromecast,
AirPlay, Android TV Remote v2, Roku, Sony Bravia etc. use different
protocols.

**Can I use this on iPhone / iPad?**
An iOS port is on the roadmap. The networking and view-model layers are
already platform-agnostic; only `ContentView.swift` would need UIKit
equivalents.

## Credits

Built by reverse-engineering the official Android app
(`com.zeasn.whalemeta`) with `jadx` and verifying every protocol detail
with live `mitmproxy` captures. Not affiliated with Zeasn or Whale TV.

## License

MIT — see `LICENSE`.
