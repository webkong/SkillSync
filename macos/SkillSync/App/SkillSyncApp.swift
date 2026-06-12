import SwiftUI
import AppKit

@main
struct SkillSyncApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
                .sheet(isPresented: $appState.showOrganizePrompt) {
                    OrganizePromptView()
                }
        }
        .windowResizability(.contentMinSize)
        Settings {
            SettingsView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Reduce tooltip delay to 300ms
        UserDefaults.standard.set(300, forKey: "NSInitialToolTipDelay")
        AppState.shared.loadInitialData()
        AppState.shared.checkOrganizeStatus()
        _ = CoreBridge.shared.startWatcher()
    }

    func applicationWillTerminate(_ notification: Notification) {
        CoreBridge.shared.stopWatcher()
    }
}
