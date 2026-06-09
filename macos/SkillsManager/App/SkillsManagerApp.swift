import SwiftUI

@main
struct SkillsManagerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
        }
        .windowResizability(.contentMinSize)
        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        AppState.shared.loadInitialData()
        _ = CoreBridge.shared.startWatcher()
    }

    func applicationWillTerminate(_ notification: Notification) {
        CoreBridge.shared.stopWatcher()
    }
}
