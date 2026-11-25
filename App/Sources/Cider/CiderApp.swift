import AppKit
import SwiftUI

@main
struct CiderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var model = AppModel()

    var body: some Scene {
        Window("Cider", id: "main") {
            RootView()
                .environment(model)
                .frame(minWidth: 980, minHeight: 680)
        }
        .defaultSize(width: 1280, height: 820)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About Cider") { model.showAbout = true }
                Button("Check for Updates…") {
                    Task { await model.updater.check(userInitiated: true) }
                    model.updater.showSheet = true
                }
            }
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Steam") {
                Button("Open Steam") { model.openSteam() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Button("Store") { model.openSteam("steam://store") }
                Button("Downloads") { model.openSteam("steam://open/downloads") }
                Divider()
                Button("Quit Steam") { model.quitSteam() }
                Button("Close All Games") { model.killEverything() }
            }
            CommandGroup(after: .sidebar) {
                Button("Library") { model.selection = .library; model.selectedGameID = nil }
                    .keyboardShortcut("1")
                Button("Steam") { model.selection = .steam; model.selectedGameID = nil }
                    .keyboardShortcut("2")
                Button("Settings") { model.selection = .settings; model.selectedGameID = nil }
                    .keyboardShortcut("3")
                Button("Diagnostics") { model.selection = .diagnostics; model.selectedGameID = nil }
                    .keyboardShortcut("4")
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    /// "Open with Cider" / drop on the Dock icon: add a game or run an installer.
    func application(_ application: NSApplication, open urls: [URL]) {
        Task { @MainActor in
            for _ in 0..<50 where AppModel.current == nil { try? await Task.sleep(nanoseconds: 100_000_000) }
            AppModel.current?.handleOpen(urls)
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // The runtime comes from a downloaded (quarantined) DMG: clear the flag on our own
        // bundled Wine so macOS doesn't block its helper binaries one by one.
        let runtime = CiderPaths.shared.runtime.path
        DispatchQueue.global(qos: .utility).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
            p.arguments = ["-dr", "com.apple.quarantine", runtime]
            p.standardError = FileHandle.nullDevice
            try? p.run()
        }
        NSApp.activate(ignoringOtherApps: true)
    }
}
