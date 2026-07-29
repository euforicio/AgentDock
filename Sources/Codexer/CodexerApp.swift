import SwiftUI

@main
struct CodexerApp: App {
    @StateObject private var model = CodexerModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 900, minHeight: 600)
                .onAppear {
                    NSApp.setActivationPolicy(.regular)
                    NSApp.activate(ignoringOtherApps: true)
                }
        }
        .defaultSize(width: 1080, height: 720)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Profile") {
                    model.showAddProfile = true
                }
                .keyboardShortcut("n", modifiers: [.command])
            }

            CommandGroup(after: .appInfo) {
                Button("View Latest Release…") {
                    guard let url = URL(string: "https://github.com/euforicio/AgentDock/releases/latest") else {
                        return
                    }
                    NSWorkspace.shared.open(url)
                }
            }

            CommandGroup(after: .textEditing) {
                Button("Search Profiles") {
                    NotificationCenter.default.post(name: .agentDockFocusSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(model)
        }
        .defaultSize(width: 840, height: 600)
        .windowStyle(.hiddenTitleBar)
    }
}
