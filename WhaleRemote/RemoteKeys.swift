import Foundation

/// Key codes that the Whale/ZEASN firmware expects inside the Seek XML payload.
/// These are the same `TR_KEY_*` constants used by the official Whale TV app —
/// recovered from the Android APK (`com.hardware.whaletv.remote.RemoteControlKeys`).
enum RemoteKeys {
    static let ok = "TR_KEY_OK"
    static let up = "TR_KEY_UP"
    static let down = "TR_KEY_DOWN"
    static let left = "TR_KEY_LEFT"
    static let right = "TR_KEY_RIGHT"
    static let back = "TR_KEY_BACK"
    static let home = "TR_KEY_SMARTTV"
    static let menu = "TR_KEY_OPTION"
    static let settings = "TR_KEY_MAINMENU"
    static let volumeUp = "TR_KEY_VOL_UP"
    static let volumeDown = "TR_KEY_VOL_DOWN"
    static let mute = "TR_KEY_MUTE"
    static let power = "TR_KEY_POWER"
    static let mouseLeft = "TR_KEY_MOUSELEFT"
    static let channelUp = "TR_KEY_CH_UP"
    static let channelDown = "TR_KEY_CH_DOWN"
    static let info = "TR_KEY_INFO"
    static let source = "TR_KEY_SOURCE"

    // Colored buttons. On Whale projectors each one triggers an image adjustment
    // in the firmware; the exact effect depends on the model.
    static let colorRed = "TR_KEY_RED"
    static let colorGreen = "TR_KEY_GREEN"
    static let colorYellow = "TR_KEY_YELLOW"
    static let colorBlue = "TR_KEY_BLUE"

    /// Enter — the official app sends it right after a `setString` to confirm text.
    static let enter = "TR_KEY_ENTER"
}
