import Foundation

/// Applies per-game fixes and launches games through Steam.
final class GameLauncher: @unchecked Sendable {
    let paths: CiderPaths
    let wine: WineEnvironment
    let steam: SteamManager

    init(paths: CiderPaths = .shared, wine: WineEnvironment, steam: SteamManager) {
        self.paths = paths
        self.wine = wine
        self.steam = steam
    }

    /// DLLs that games ship and that must win over Wine's builtin versions. With Wine's own
    /// copies some games crash on start (e.g. Halo Wars: Definitive Edition).
    static let nativeFirstDLLs = ["d3dcompiler_47", "d3dcompiler_46", "d3dcompiler_43", "concrt140", "msvcp140",
                                  "msvcp140_1", "msvcp140_2", "vcruntime140", "vcruntime140_1", "vccorlib140"]

    /// Games whose Steam "Anti-Cheat Disabled" launch option is a plain executable. Kernel/EAC
    /// anti-cheat can't run under Wine, so Cider launches these directly (Steam must be running).
    static let antiCheatFree: [Int: String] = [
        976730: "MCC\\Binaries\\Win64\\MCC-Win64-Shipping.exe", // Halo: The Master Chief Collection
    ]

    struct Fixes: Sendable {
        var executables: [String] = []
        var dlls: [String] = []
    }

    /// Scans the game folder: which of `nativeFirstDLLs` it ships and which executables it has.
    func detectFixes(for game: Game) -> Fixes {
        let fm = FileManager.default
        var fixes = Fixes()
        var dlls = Set<String>()
        guard let e = fm.enumerator(at: game.installDir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { return fixes }
        var exes = Set<String>()
        for case let url as URL in e {
            // Games outside Steam may live in big folders (Downloads…): stay shallow there.
            if e.level > (game.isCustom ? 2 : 5) { e.skipDescendants(); continue }
            let name = url.lastPathComponent.lowercased()
            if name.hasSuffix(".exe") { exes.insert(url.lastPathComponent) }
            if name.hasSuffix(".dll") {
                let base = String(name.dropLast(4))
                if Self.nativeFirstDLLs.contains(base) { dlls.insert(base) }
            }
        }
        fixes.executables = exes.sorted()
        fixes.dlls = dlls.sorted()
        return fixes
    }

    /// Writes `HKCU\Software\Wine\AppDefaults\<exe>\DllOverrides` = native,builtin for each DLL.
    func applyFixes(for game: Game) async {
        let fixes = detectFixes(for: game)
        guard !fixes.dlls.isEmpty, !fixes.executables.isEmpty else { return }
        var body = ""
        for exe in fixes.executables {
            body += "[HKEY_CURRENT_USER\\Software\\Wine\\AppDefaults\\\(WineEnvironment.regEscape(exe))\\DllOverrides]\n"
            for dll in fixes.dlls { body += "\"\(dll)\"=\"native,builtin\"\n" }
            body += "\n"
        }
        wine.appendLog("Fixes for \(game.name): \(fixes.dlls.joined(separator: ",")) on \(fixes.executables.count) exe(s)")
        try? await wine.importRegistry(body)
    }

    /// Launches a game. Restarts Steam if it's running with a different desktop / environment.
    /// `direct` is a Windows path relative to the game folder to run instead of `-applaunch`.
    func launch(_ game: Game, session: SteamSession, current: SteamSession?, language: String,
                extraArgs: [String], direct: String? = nil) async throws -> SteamSession {
        await applyFixes(for: game)
        steam.patchWebhelper()
        let running = steam.isSteamRunning()
        let sameSession = running && current == session
        if running && !sameSession {
            wine.appendLog("Restarting Steam with \(session)")
            try await steam.shutdown()
        }
        if let direct {
            if !sameSession { try await steam.start(session: session, language: language, extra: ["-silent"]) }
            await steam.waitUntilSignedIn(timeout: 120)
            try launchDirect(game, relativeExe: direct, session: session, extraArgs: extraArgs)
            return session
        }
        if sameSession {
            try steam.send(["-applaunch", String(game.appID)] + extraArgs, language: language)
        } else {
            try await steam.start(session: session, language: language,
                                  extra: ["-silent", "-applaunch", String(game.appID)] + extraArgs)
        }
        return session
    }

    /// Runs the game's executable ourselves, telling Steamworks which app it is.
    private func launchDirect(_ game: Game, relativeExe: String, session: SteamSession, extraArgs: [String]) throws {
        let winGameDir = "C:\\Program Files (x86)\\Steam\\steamapps\\common\\\(game.installDir.lastPathComponent)"
        let exe = winGameDir + "\\" + relativeExe
        var opts = WineEnvironment.Options()
        opts.fpsHUD = session.fpsHUD
        opts.msync = session.msync
        opts.resizableWindows = session.resizable ?? true
        opts.renderScale = session.renderScale
        let id = String(game.appID)
        opts.extra = ["SteamAppId": id, "SteamGameId": id, "SteamOverlayGameId": id]
        var args: [String] = []
        if let desktop = session.desktop { args = ["explorer", "/desktop=Cider,\(desktop)"] }
        args += [exe] + extraArgs
        wine.appendLog("Launching \(game.name) directly (no anti-cheat): \(relativeExe)")
        try wine.spawn(args, options: opts, cwd: game.installDir)
    }

    /// Runs a game added from outside Steam. Steam keeps running unless it was started with a
    /// different display configuration (Windows shares screen geometry between all programs).
    func launchCustom(_ game: Game, session: SteamSession, current: SteamSession?, extraArgs: [String]) async throws {
        guard let exe = game.customExe else { return }
        await applyFixes(for: game)
        if steam.isSteamRunning(), let current,
           current.desktop != session.desktop || (current.renderScale ?? 1) != (session.renderScale ?? 1)
            || (current.resizable ?? true) != (session.resizable ?? true) {
            wine.appendLog("Closing Steam: \(game.name) needs a different display configuration")
            try await steam.shutdown()
        }
        var opts = WineEnvironment.Options()
        opts.fpsHUD = session.fpsHUD
        opts.msync = session.msync
        opts.resizableWindows = session.resizable ?? true
        opts.renderScale = session.renderScale
        var args: [String] = []
        if let desktop = session.desktop {
            args = ["explorer", "/desktop=Cider,\(desktop)", WineEnvironment.windowsPath(exe)]
        } else {
            args = [exe.path]
        }
        args += extraArgs
        wine.appendLog("Launching \(game.name) (outside Steam): \(exe.path)")
        try wine.spawn(args, options: opts, cwd: exe.deletingLastPathComponent())
    }

    /// True when a process of the game is running (matched by its install folder).
    static func isRunning(_ game: Game, in procs: [ProcessScanner.WinProcess]) -> Bool {
        if let exe = game.customExe {
            let name = exe.lastPathComponent.lowercased()
            let dir = ProcessScanner.canonicalPath(exe.deletingLastPathComponent().path)
            return procs.contains { p in
                p.lowercased.contains(name) &&
                    (p.lowercased.contains(dir.lowercased()) || p.cwd?.hasPrefix(dir) == true
                     || p.lowercased.contains(WineEnvironment.windowsPath(exe).lowercased()))
            }
        }
        let dir = game.installDir.lastPathComponent.lowercased()
        let win = "\\steamapps\\common\\\(dir)\\"
        let unix = "/steamapps/common/\(dir)/"
        return procs.contains { $0.lowercased.contains(win) || $0.lowercased.contains(unix) }
    }
}
