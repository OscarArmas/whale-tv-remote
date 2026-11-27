import SwiftUI

/// Desktop app entry point. Pure LAN remote, no account, no telemetry.
@main
struct WhaleRemoteApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 420, height: 720)
    }
}
