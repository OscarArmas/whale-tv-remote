import Foundation

/// Version string shown in the UI footer and injected into Info.plist by build.sh.
/// Bump this on every DMG so the user can tell which build is open — Finder
/// sometimes keeps older copies in /Applications.
enum AppVersion {
    static let short = "1.9.4"
    static let build = "14"

    static var footer: String {
        "App v\(short)  ·  build \(build)"
    }
}
