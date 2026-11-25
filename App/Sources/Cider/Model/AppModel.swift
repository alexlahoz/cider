import AppKit
import Foundation
import Observation
import SwiftUI

enum SidebarItem: String, Hashable, CaseIterable, Identifiable {
    case library, steam, settings, diagnostics
    var id: String { rawValue }

    var title: LocalizedStringKey {
        switch self {
        case .library: return "Library"
        case .steam: return "Steam"
        case .settings: return "Settings"
        case .diagnostics: return "Diagnostics"
        }
    }

    var symbol: String {
        switch self {
        case .library: return "square.grid.2x2.fill"
        case .steam: return "bag.fill"
        case .settings: return "gearshape.fill"
        case .diagnostics: return "stethoscope"
        }
    }
}

enum GameActivity: Equatable {
    case idle, launching, running
}

@Observable
@MainActor
final class AppModel {
    let paths = CiderPaths.shared
    let wine: WineEnvironment
    let steam: SteamManager
    let launcher: GameLauncher
    let library: SteamLibrary
    let setup: SetupModel
    let updater = Updater()

    var state: PersistentState { didSet { if !demoMode { state.save(to: paths.stateFile) } } }
    var games: [Game] = []
    var activity: [Int: GameActivity] = [:]
    /// Games being closed from Cider ("Close Game").
    var closing: Set<Int> = []
    var steamRunning = false
    var steamUser: SteamManager.SteamUser?
    var selection: SidebarItem = .library
    var selectedGameID: Int?
    var showOnboarding: Bool
    var showAbout = false
    var toast: Toast?
    var busyMessage: LocalizedStringKey?
    var demoMode = false

    private var sessionStarts: [Int: Date] = [:]
    private var hiddenForGame = false
    private var launchDeadline: [Int: Date] = [:]
    private var monitorTask: Task<Void, Never>?
    private var lastLibraryStamp: Date?

    struct Toast: Identifiable, Equatable {
        let id = UUID()
        let message: String
        var isError = false
    }

    /// The live model, for AppKit callbacks (Finder "Open with").
    static weak var current: AppModel?

    init() {
        let wine = WineEnvironment()
        let steam = SteamManager(wine: wine)
        self.wine = wine
        self.steam = steam
        self.launcher = GameLauncher(wine: wine, steam: steam)
        self.library = SteamLibrary(paths: .shared)
        let state = PersistentState.load(from: CiderPaths.shared.stateFile)
        self.state = state
        let defaults = UserDefaults.standard
        self.demoMode = defaults.bool(forKey: "CiderDemo")
        self.showOnboarding = !state.onboardingComplete || defaults.string(forKey: "CiderOnboardingPreview") != nil
        self.setup = SetupModel()
        setup.model = self
        if let s = defaults.string(forKey: "CiderSection"), let item = SidebarItem(rawValue: s) { selection = item }
        if demoMode {
            loadDemo()
            showOnboarding = defaults.string(forKey: "CiderOnboardingPreview") != nil
        } else {
            reloadLibrary()
            steamUser = steam.currentUser
        }
        if defaults.integer(forKey: "CiderDetail") != 0 { selectedGameID = defaults.integer(forKey: "CiderDetail") }
        if let preview = defaults.string(forKey: "CiderOnboardingPreview") {
            setup.preview(preview)
        }
        startMonitor()
        Self.current = self
        if !demoMode { updater.checkOnLaunch() }
    }

    // MARK: settings

    var language: String { state.settings.steamLanguage.steamName }

    func settings(for game: Game) -> GameSettings { state.games[String(game.appID)] ?? GameSettings() }

    func updateSettings(for game: Game, _ change: (inout GameSettings) -> Void) {
        var s = settings(for: game)
        change(&s)
        state.games[String(game.appID)] = s
    }

    func effectiveDisplay(for game: Game) -> DisplayMode { (settings(for: game).display ?? state.settings.defaultDisplay).normalized }

    func session(for game: Game?) -> SteamSession {
        let s = game.map { settings(for: $0) } ?? GameSettings()
        let display = game.map { effectiveDisplay(for: $0) } ?? state.settings.defaultDisplay.normalized
        return SteamSession(desktop: display.desktopSize,
                            fpsHUD: s.fpsHUD ?? state.settings.fpsHUD,
                            msync: s.msync ?? state.settings.msync,
                            resizable: state.settings.resizableWindows ?? true,
                            renderScale: (s.renderScale ?? 1) > 1 ? s.renderScale : nil)
    }

    var hasAntiCheatFreeMode: (Game) -> Bool { { GameLauncher.antiCheatFree[$0.appID] != nil } }

    /// Known games default to windowed when they run as normal macOS windows.
    func opensWindowed(_ game: Game) -> Bool {
        settings(for: game).windowed ?? (effectiveDisplay(for: game) == .native)
    }

    func skipsAntiCheat(_ game: Game) -> Bool {
        hasAntiCheatFreeMode(game) && (settings(for: game).skipAntiCheat ?? true)
    }

    func stats(for game: Game) -> PlayStats { state.stats[String(game.appID)] ?? PlayStats() }

    func lastPlayed(_ game: Game) -> Date? {
        [game.lastPlayed, stats(for: game).lastPlayed].compactMap { $0 }.max()
    }

    func playtimeMinutes(_ game: Game) -> Int {
        max(game.playtimeMinutes ?? 0, Int(stats(for: game).totalSeconds / 60))
    }

    func graphics(for game: Game) -> GraphicsInfo? { state.graphics[String(game.appID)] }

    var recentlyPlayed: [Game] {
        games.filter { lastPlayed($0) != nil }.sorted { lastPlayed($0)! > lastPlayed($1)! }
    }

    // MARK: library

    func reloadLibrary() {
        guard !demoMode else { return }
        let lib = library
        let custom = (state.customGames ?? []).map(\.asGame)
        Task.detached(priority: .utility) {
            let found = (lib.games() + custom).sorted { $0.sortName < $1.sortName }
            await MainActor.run {
                self.games = found
                self.probeGraphics()
            }
        }
    }

    private func probeGraphics() {
        let missing = games.filter { state.graphics[String($0.appID)] == nil && $0.isInstalled }
        guard !missing.isEmpty else { return }
        Task.detached(priority: .background) {
            var found: [Int: GraphicsInfo] = [:]
            for g in missing {
                let info = g.customExe.flatMap { GraphicsProbe.inspect($0) } ?? GraphicsProbe.probe(gameDir: g.installDir)
                if let info { found[g.appID] = info }
            }
            await MainActor.run {
                for (id, info) in found { self.state.graphics[String(id)] = info }
            }
        }
    }

    private var libraryStamp: Date? {
        library.libraryFolders().compactMap {
            try? $0.appendingPathComponent("steamapps").resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        }.max()
    }

    // MARK: monitoring

    private func startMonitor() {
        monitorTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.tick()
                try? await Task.sleep(nanoseconds: 2_500_000_000)
            }
        }
    }

    private func tick() async {
        guard !demoMode else { return }
        let data = paths.data
        let all = await Task.detached(priority: .utility) { ProcessScanner.allWindowsProcesses() }.value
        let root = ProcessScanner.canonicalPath(data.path)
        let procs = all.filter { $0.cwd?.hasPrefix(root) == true }
        let running = steam.isSteamRunning(procs)
        if running != steamRunning { steamRunning = running }
        let user = steam.currentUser
        if user != steamUser { steamUser = user }
        let now = Date()
        for game in games {
            let isUp = GameLauncher.isRunning(game, in: game.isCustom ? all : procs)
            let current = activity[game.appID] ?? .idle
            if isUp {
                if current != .running {
                    activity[game.appID] = .running
                    sessionStarts[game.appID] = now
                    launchDeadline[game.appID] = nil
                    // Step aside so the game gets the whole Mac (no glass window to composite).
                    if state.settings.hideWhilePlaying ?? true, NSApp.isActive || current == .launching {
                        hiddenForGame = true
                        NSApp.hide(nil)
                    }
                }
            } else if current == .running {
                activity[game.appID] = .idle
                closing.remove(game.appID)
                recordSession(game, end: now)
                if hiddenForGame && !activity.values.contains(.running) {
                    hiddenForGame = false
                    NSApp.unhide(nil)
                }
            } else if current == .launching, let deadline = launchDeadline[game.appID], now > deadline {
                activity[game.appID] = .idle
                launchDeadline[game.appID] = nil
                showToast(String(localized: "\(game.name) didn't open. Check the Steam window."), error: true)
            }
        }
        if let stamp = libraryStamp, stamp != lastLibraryStamp {
            lastLibraryStamp = stamp
            reloadLibrary()
        }
    }

    private func recordSession(_ game: Game, end: Date) {
        guard let start = sessionStarts.removeValue(forKey: game.appID) else { return }
        var s = stats(for: game)
        s.totalSeconds += end.timeIntervalSince(start)
        s.lastPlayed = end
        state.stats[String(game.appID)] = s
    }

    // MARK: actions

    func play(_ game: Game) {
        guard activity[game.appID, default: .idle] == .idle else { return }
        if demoMode {
            activity[game.appID] = .launching
            Task {
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                activity[game.appID] = .running
            }
            return
        }
        if graphics(for: game)?.api == .dx12 {
            showToast(String(localized: "\(game.name) uses DirectX 12, which Cider doesn't support yet. It may not start."), error: true)
        }
        activity[game.appID] = .launching
        launchDeadline[game.appID] = Date().addingTimeInterval(240)
        let session = session(for: game)
        let current = state.lastSession
        var args = settings(for: game).extraArguments.split(separator: " ").map(String.init)
        let language = language
        let direct = skipsAntiCheat(game) ? GameLauncher.antiCheatFree[game.appID] : nil
        let windowed = opensWindowed(game)
        if GameWindowConfig.isSupported(game.appID) {
            // Games whose settings file Cider knows: set the mode there.
            GameWindowConfig.apply(appID: game.appID, windowed: windowed, prefix: paths)
        } else if windowed {
            // Everyone else: ask the engine (Unity / Unreal / Source) on the command line.
            let extra = GameWindowConfig.windowedArguments(for: GameWindowConfig.engine(of: game.installDir))
            if !extra.isEmpty && !args.contains(extra[0]) { args += extra }
        }
        if game.isCustom {
            Task {
                do {
                    try await launcher.launchCustom(game, session: session, current: current, extraArgs: args)
                } catch {
                    activity[game.appID] = .idle
                    showToast(error.localizedDescription, error: true)
                }
            }
            return
        }
        Task {
            do {
                let used = try await launcher.launch(game, session: session, current: current, language: language,
                                                     extraArgs: args, direct: direct)
                state.lastSession = used
            } catch {
                activity[game.appID] = .idle
                showToast(error.localizedDescription, error: true)
            }
        }
    }

    private var openingSteam = false

    // MARK: games from outside Steam

    /// Files opened with Cider: installers run, executables are added to the library.
    func handleOpen(_ urls: [URL]) {
        for url in urls {
            let ext = url.pathExtension.lowercased()
            let name = url.lastPathComponent.lowercased()
            if ext == "msi" || (ext == "exe" && (name.contains("setup") || name.contains("install"))) {
                runInstaller(url)
            } else if ext == "exe" {
                addCustomGame(exe: url)
            }
        }
        selection = .library
        selectedGameID = nil
        NSApp.activate(ignoringOtherApps: true)
    }

    var installerRunning = false
    /// Executables an installer just created, offered to the user to add.
    var installerResults: [URL]? = nil

    func customGame(for game: Game) -> CustomGame? {
        (state.customGames ?? []).first { $0.numericID == game.appID }
    }

    /// Adds a Windows executable to the library (name guessed, artwork looked up on Steam).
    func addCustomGame(exe: URL) {
        guard exe.pathExtension.lowercased() == "exe" else {
            showToast(String(localized: "Choose the game's .exe file."), error: true); return
        }
        if (state.customGames ?? []).contains(where: { $0.exePath == exe.path }) {
            showToast(String(localized: "That game is already in your library.")); return
        }
        let game = CustomGame(name: Self.guessName(for: exe), exePath: exe.path)
        state.customGames = (state.customGames ?? []) + [game]
        reloadLibrary()
        showToast(String(localized: "\(game.name) added to your library."))
        let id = game.id, name = game.name
        let dir = exe.deletingLastPathComponent()
        Task {
            let size = await Task.detached(priority: .utility) { Self.folderSize(dir, limitDepth: 6) }.value
            if var list = state.customGames, let i = list.firstIndex(where: { $0.id == id }) {
                list[i].sizeBytes = size
                state.customGames = list
            }
            if let match = await StoreSearch.bestMatch(for: name) { setArtwork(id: id, appID: match) } else { reloadLibrary() }
        }
    }

    func setArtwork(id: UUID, appID: Int?) {
        guard var list = state.customGames, let i = list.firstIndex(where: { $0.id == id }) else { return }
        list[i].artworkAppID = appID
        state.customGames = list
        state.graphics[String(list[i].numericID)] = nil
        reloadLibrary()
    }

    func refreshArtwork(_ game: Game) {
        guard let c = customGame(for: game) else { return }
        Task {
            let match = await StoreSearch.bestMatch(for: c.name)
            setArtwork(id: c.id, appID: match)
            showToast(match == nil ? String(localized: "Couldn't find \(c.name) on Steam.") : String(localized: "Artwork updated."),
                      error: match == nil)
        }
    }

    func renameCustomGame(_ game: Game, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, var list = state.customGames,
              let i = list.firstIndex(where: { $0.numericID == game.appID }) else { return }
        list[i].name = trimmed
        state.customGames = list
        reloadLibrary()
        refreshArtwork(list[i].asGame)
    }

    func removeCustomGame(_ game: Game) {
        state.customGames = (state.customGames ?? []).filter { $0.numericID != game.appID }
        state.games[String(game.appID)] = nil
        if selectedGameID == game.appID { selectedGameID = nil }
        reloadLibrary()
    }

    /// Runs an installer (.exe / .msi) inside Cider's Windows, then offers the new executables.
    func runInstaller(_ url: URL) {
        guard !installerRunning else { return }
        installerRunning = true
        let before = Self.installedExecutables(in: paths)
        let ext = url.pathExtension.lowercased()
        let args = ext == "msi" ? ["msiexec", "/i", WineEnvironment.windowsPath(url)] : [url.path]
        showToast(String(localized: "Follow the installer's steps. Cider will look for the game when it finishes."))
        let paths = paths
        do {
            try wine.spawn(args, cwd: url.deletingLastPathComponent()) { [weak self] _ in
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                    let after = Self.installedExecutables(in: paths)
                    let new = after.subtracting(before)
                        .filter { !GraphicsProbe.ignoredExecutables.contains(where: $0.lastPathComponent.lowercased().contains) }
                        .sorted { $0.path < $1.path }
                    self?.installerRunning = false
                    self?.installerResults = new
                }
            }
        } catch {
            installerRunning = false
            showToast(error.localizedDescription, error: true)
        }
    }

    nonisolated static func installedExecutables(in paths: CiderPaths) -> Set<URL> {
        let c = paths.driveC
        let user = NSUserName()
        let roots = ["Program Files", "Program Files (x86)", "Games", "GOG Games",
                     "users/\(user)/AppData/Local/Programs", "users/\(user)/AppData/Roaming"]
        var out = Set<URL>()
        for r in roots {
            let dir = c.appendingPathComponent(r, isDirectory: true)
            guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]) else { continue }
            for case let f as URL in e {
                if e.level > 5 { e.skipDescendants(); continue }
                if f.lastPathComponent.hasPrefix("Steam") && e.level == 1 { e.skipDescendants(); continue }
                if f.pathExtension.lowercased() == "exe" { out.insert(f.standardizedFileURL) }
            }
        }
        return out
    }

    nonisolated static func guessName(for exe: URL) -> String {
        let generic: Set<String> = ["launcher", "game", "start", "play", "setup", "main", "client", "app", "run", "bin",
                                    "binaries", "win64", "win32", "x64", "x86", "64", "32", "release", "shipping"]
        var base = exe.deletingPathExtension().lastPathComponent
        base = base.replacingOccurrences(of: "-Win64-Shipping", with: "").replacingOccurrences(of: "_", with: " ")
        if generic.contains(base.lowercased()) || base.count <= 2 {
            var dir = exe.deletingLastPathComponent()
            while generic.contains(dir.lastPathComponent.lowercased()) && dir.pathComponents.count > 2 {
                dir = dir.deletingLastPathComponent()
            }
            base = dir.lastPathComponent
        }
        // "MyCoolGame" -> "My Cool Game"
        var out = ""
        for (i, ch) in base.enumerated() {
            if i > 0, ch.isUppercase, let prev = out.last, prev.isLowercase { out.append(" ") }
            out.append(ch)
        }
        out = out.trimmingCharacters(in: .whitespaces)
        // "hollow knight" -> "Hollow Knight"
        if out == out.lowercased() { out = out.capitalized }
        return out
    }

    nonisolated static func folderSize(_ dir: URL, limitDepth: Int) -> Int64 {
        var total: Int64 = 0
        guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) else { return 0 }
        for case let f as URL in e {
            if e.level > limitDepth { e.skipDescendants(); continue }
            total += Int64((try? f.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0)
        }
        return total
    }

    /// Before an update replaces the app: quit Steam and any game (they run from inside the bundle).
    func prepareForUpdate() async {
        try? await steam.shutdown()
        await wine.killAll()
    }

    /// Steam is optional: true once its client is installed and up to date.
    var steamAvailable: Bool { demoMode || (steam.isInstalled && steam.isBootstrapped) }

    /// Runs the Steam part of the first-run assistant (when it was skipped).
    func installSteam() {
        setup.reset()
        withAnimation(.spring(duration: 0.6)) { showOnboarding = true }
        setup.start()
    }

    func openSteam(_ uri: String? = nil) {
        guard !demoMode, !openingSteam else { return }
        guard steamAvailable else {
            selection = .steam
            selectedGameID = nil
            return
        }
        openingSteam = true
        Task {
            defer { openingSteam = false }
            do {
                if steam.isSteamRunning() {
                    try steam.send(uri.map { [$0] } ?? ["steam://open/main"], language: language)
                } else {
                    let session = session(for: nil)
                    try await steam.start(session: session, language: language, extra: uri.map { [$0] } ?? [])
                    state.lastSession = session
                }
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                bringWineToFront()
            } catch {
                showToast(error.localizedDescription, error: true)
            }
        }
    }

    /// Steam's windows belong to Wine processes: bring them in front of Cider.
    func bringWineToFront() {
        let procs = steam.processes()
        let preferred = procs.filter { $0.lowercased.contains("explorer.exe /desktop") } + procs.filter { $0.lowercased.contains("steamwebhelper") }
        for p in preferred {
            if let app = NSRunningApplication(processIdentifier: p.pid), app.activationPolicy != .prohibited {
                app.activate()
                return
            }
        }
    }

    func quitSteam() {
        Task {
            busyMessage = "Quitting Steam…"
            try? await steam.shutdown()
            busyMessage = nil
            steamRunning = false
        }
    }

    /// Closes a running game (the "Playing" button's "Close Game"). Steam stays open.
    func stopGame(_ game: Game) {
        guard activity[game.appID] == .running, !closing.contains(game.appID) else { return }
        closing.insert(game.appID)
        if demoMode {
            Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                activity[game.appID] = .idle
                closing.remove(game.appID)
            }
            return
        }
        let dataDir = paths.data
        wine.appendLog("Closing \(game.name) from Cider")
        Task {
            let closed = await GameLauncher.stop(game, dataDir: dataDir)
            await tick()
            closing.remove(game.appID)
            if !closed {
                showToast(String(localized: "\(game.name) couldn't be closed."), error: true)
            }
        }
    }

    func killEverything() {
        Task {
            busyMessage = "Closing everything…"
            await wine.killAll()
            for (id, a) in activity where a != .idle {
                if let g = games.first(where: { $0.appID == id }) { recordSession(g, end: Date()) }
                activity[id] = .idle
            }
            busyMessage = nil
            steamRunning = false
            showToast(String(localized: "Steam and all games have been closed."))
        }
    }

    func repairEnvironment() {
        Task {
            busyMessage = "Repairing the environment…"
            await wine.killAll()
            var opts = WineEnvironment.Options()
            opts.extra["WINEDLLOVERRIDES"] = "mscoree,mshtml="
            _ = try? await wine.run(["wineboot", "-u"], options: opts, timeout: 600)
            await wine.waitForServer(timeout: 120)
            try? await steam.applyPrefixDefaults(language: language)
            steam.patchWebhelper()
            try? await steam.installService()
            await wine.killAll()
            state.graphics = [:]
            reloadLibrary()
            busyMessage = nil
            showToast(String(localized: "Environment repaired."))
        }
    }

    func resetEverything() {
        Task {
            busyMessage = "Deleting game data…"
            await wine.killAll()
            try? FileManager.default.removeItem(at: paths.prefix)
            var s = PersistentState()
            s.settings = state.settings
            state = s
            games = []
            busyMessage = nil
            setup.reset()
            withAnimation(.spring(duration: 0.6)) { showOnboarding = true }
        }
    }

    func finishOnboarding() {
        state.onboardingComplete = true
        reloadLibrary()
        steamUser = steam.currentUser
        withAnimation(.spring(duration: 0.7, bounce: 0.15)) { showOnboarding = false }
    }

    func showToast(_ message: String, error: Bool = false) {
        withAnimation(.spring) { toast = Toast(message: message, isError: error) }
        let id = toast?.id
        Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            if toast?.id == id { withAnimation(.easeOut) { toast = nil } }
        }
    }

    func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: demo data (screenshots / design review only)

    private func loadDemo() {
        let sample: [(Int, String, Int, Int)] = [
            (459220, "Halo Wars: Definitive Edition", 2_710, 10_077_325_749),
            (1145360, "Hades", 3_900, 15_000_000_000),
            (413150, "Stardew Valley", 12_400, 650_000_000),
            (367520, "Hollow Knight", 5_200, 9_000_000_000),
            (504230, "Celeste", 900, 1_200_000_000),
            (292030, "The Witcher 3: Wild Hunt", 0, 50_000_000_000),
            (620, "Portal 2", 640, 12_000_000_000),
            (646570, "Slay the Spire", 1_800, 1_000_000_000),
        ]
        games = sample.enumerated().map { i, s in
            Game(appID: s.0, name: s.1, installDir: URL(fileURLWithPath: "/tmp/\(s.0)"), sizeOnDisk: Int64(s.3),
                 stateFlags: i == 5 ? 6 : 4,
                 lastPlayed: s.2 > 0 ? Date().addingTimeInterval(-Double(i * 86_400 + 3_600 * (i + 1))) : nil,
                 playtimeMinutes: s.2)
        }
        activity[1145360] = .running
        steamRunning = true
        steamUser = .init(steamID: "1", accountName: "demo", personaName: String(localized: "Player"), mostRecent: true)
        for g in games {
            state.graphics[String(g.appID)] = GraphicsInfo(api: g.appID == 620 ? .dx9 : .dx11, is64Bit: true, executable: "game.exe")
        }
    }
}
