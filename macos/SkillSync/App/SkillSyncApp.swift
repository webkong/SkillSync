import SwiftUI
import AppKit

private enum AppWindow {
    static let main = "main"
}

@main
struct SkillSyncApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var appState = AppState.shared

    var body: some Scene {
        WindowGroup(id: AppWindow.main) {
            ContentView()
                .frame(minWidth: 900, minHeight: 600)
                .sheet(isPresented: $appState.showOrganizePrompt) {
                    OrganizePromptView()
                }
        }
        .windowResizability(.contentMinSize)
        MenuBarExtra {
            SkillSyncMenuBarView()
        } label: {
            Image("MenuBarIcon")
                .renderingMode(.template)
        }
        .menuBarExtraStyle(.menu)
        Settings {
            SettingsView()
        }
    }
}

private struct SkillSyncMenuBarView: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Open SkillSync") {
            showMainWindow()
        }

        Divider()

        Button("Quit SkillSync") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func showMainWindow() {
        if let window = NSApp.windows.first(where: { $0.canBecomeMain && !$0.isMiniaturized }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openWindow(id: AppWindow.main)
        }
        NSApp.activate(ignoringOtherApps: true)
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
