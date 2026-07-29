import CodexerCore
import Foundation

@main
struct CodexerShortcutLauncher {
    static func main() async {
        do {
            _ = try await ShortcutLauncherRunner().run(resourceURL: Bundle.main.resourceURL)
        } catch {
            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            FileHandle.standardError.write(Data("AgentDock shortcut failed: \(message)\n".utf8))
            exit(1)
        }
    }
}
