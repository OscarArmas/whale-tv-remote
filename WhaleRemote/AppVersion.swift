import Foundation

enum AppVersion {
    static var footer: String {
        let info = Bundle.main.infoDictionary
        guard let version = info?["CFBundleShortVersionString"] as? String,
              let build = info?["CFBundleVersion"] as? String else { return "Development build" }
        return "App v\(version)  ·  build \(build)"
    }
}
