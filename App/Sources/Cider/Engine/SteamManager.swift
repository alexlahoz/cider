import Foundation

/// Installs, patches, starts and inspects Steam for Windows inside Cider's prefix.
final class SteamManager: @unchecked Sendable {
    static let installerURL = URL(string: "https://cdn.cloudflare.steamstatic.com/client/installer/SteamSetup.exe")!

    let paths: CiderPaths
    let wine: WineEnvironment

    init(paths: CiderPaths = .shared, wine: WineEnvironment) {
        self.paths = paths
        self.wine = wine
    }

    enum SteamError: LocalizedError {
        case installerFailed
        case bootstrapTimeout
        case runtimeMissing

        var errorDescription: String? {
            switch self {
            case .installerFailed: return String(localized: "Steam couldn't be installed.")
            case .bootstrapTimeout: return String(localized: "Steam took too long to update.")
            case .runtimeMissing: return String(localized: "The game engine is missing inside Cider. Download the app again.")
            }
        }
    }

    // MARK: state

    var isInstalled: Bool { FileManager.default.fileExists(atPath: paths.steamExe.path) }

    /// Steam has finished its first self-update (client files are in place).
    var isBootstrapped: Bool {
        FileManager.default.fileExists(atPath: paths.steamWebhelperDir.appendingPathComponent("steamwebhelper.exe").path)
            && FileManager.default.fileExists(atPath: paths.steam.appendingPathComponent("steamui.dll").path)
    }

    var hasLoggedInUser: Bool { !loginUsers().isEmpty }

    struct SteamUser: Sendable, Hashable {
        let steamID: String
        let accountName: String
        let personaName: String
        let mostRecent: Bool
    }

    func loginUsers() -> [SteamUser] {
        guard let vdf = VDF.parse(contentsOf: paths.steam.appendingPathComponent("config/loginusers.vdf")),
              let users = vdf["users"] else { return [] }
        return users.children.map { id, u in
            SteamUser(steamID: id,
                      accountName: u["AccountName"]?.string ?? "",
                      personaName: u["PersonaName"]?.string ?? "",
                      mostRecent: u["MostRecent"]?.string == "1")
        }
    }

    var currentUser: SteamUser? {
        let users = loginUsers()
        return users.first(where: \.mostRecent) ?? users.first
    }

    func processes() -> [ProcessScanner.WinProcess] {
        ProcessScanner.processes(under: paths.data)
    }

    /// Steam's own process (not the web helper, whose arguments also mention steam.exe).
    func isSteamRunning(_ procs: [ProcessScanner.WinProcess]? = nil) -> Bool {
        (procs ?? processes()).contains { p in
            let c = p.lowercased
            guard let r = c.range(of: ".exe") else { return false }
            let exe = c[..<r.upperBound]
            return exe.hasSuffix("\\steam.exe") || exe.hasSuffix("/steam.exe")
        }
    }

    /// Reads `ActiveUser` from the live registry: non-zero once someone is signed in.
    func activeUserID() async -> Int {
        let out = await wine.capture(["reg", "query", "HKCU\\Software\\Valve\\Steam\\ActiveProcess", "/v", "ActiveUser"])
        guard let line = out.split(separator: "\n").first(where: { $0.contains("ActiveUser") }),
              let hex = line.split(separator: " ").last?.replacingOccurrences(of: "0x", with: "") else { return 0 }
        return Int(hex.trimmingCharacters(in: .whitespacesAndNewlines), radix: 16) ?? 0
    }

    /// Waits for Steam to report a signed-in user (needed before starting a game directly).
    func waitUntilSignedIn(timeout: TimeInterval) async {
        let start = Date()
        while Date().timeIntervalSince(start) < timeout {
            if isSteamRunning(), await activeUserID() != 0 {
                // Give the client a moment to finish its own start-up before a game talks to it.
                try? await Task.sleep(nanoseconds: 6_000_000_000)
                return
            }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
    }

    // MARK: setup steps

    /// Creates the Windows prefix and applies Cider's defaults.
    func createPrefix(language: String) async throws {
        guard paths.runtimeIsPresent else { throw SteamError.runtimeMissing }
        paths.ensureDirectories()
        // Mono and Gecko are not shipped: disable them so wineboot doesn't offer to download them.
        var opts = WineEnvironment.Options()
        opts.extra["WINEDLLOVERRIDES"] = "mscoree,mshtml="
        try await wine.run(["wineboot", "--init"], options: opts, timeout: 600)
        await wine.waitForServer(timeout: 120)
        try await applyPrefixDefaults(language: language)
    }

    func applyPrefixDefaults(language: String) async throws {
        try await wine.importRegistry("""
        [HKEY_CURRENT_USER\\Software\\Wine\\Mac Driver]
        "RetinaMode"="n"
        "CaptureDisplaysForFullscreen"="y"

        [HKEY_CURRENT_USER\\Software\\Wine\\Explorer\\Desktops]
        "Cider"="1920x1080"

        [HKEY_CURRENT_USER\\Software\\Valve\\Steam]
        "Language"="\(language)"
        """)
        installWinemetal()
    }

    /// DXMT's PE side must also be present in system32.
    func installWinemetal() {
        let dest = paths.system32.appendingPathComponent("winemetal.dll")
        try? FileManager.default.removeItem(at: dest)
        try? FileManager.default.copyItem(at: paths.winemetalDLL, to: dest)
    }

    /// Downloads the official installer from Valve.
    func downloadInstaller(progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        paths.ensureDirectories()
        let dest = paths.downloads.appendingPathComponent("SteamSetup.exe")
        let delegate = DownloadProgressDelegate(progress: progress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        let (tmp, response) = try await session.download(from: Self.installerURL)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        try? FileManager.default.removeItem(at: dest)
        try FileManager.default.moveItem(at: tmp, to: dest)
        progress(1)
        return dest
    }

    /// Runs SteamSetup.exe silently.
    func runInstaller(_ installer: URL) async throws {
        try await wine.run([installer.path, "/S"], timeout: 600)
        await wine.waitForServer(timeout: 60)
        guard isInstalled else { throw SteamError.installerFailed }
    }

    /// First start of Steam: it downloads and installs the full client (~350 MB, two stages).
    /// `progress` gets (fraction, downloadedKB, totalKB).
    func bootstrap(language: String, progress: @escaping @Sendable (Double, Int, Int) -> Void,
                   onStall: @escaping @Sendable () -> Void = {}) async throws {
        try? FileManager.default.removeItem(at: paths.steamBootstrapLog)
        // No -noverifyfiles here: with it the updater skips the first download and just quits.
        let args = [paths.steamExe.path] + baseArguments(language: language).filter { $0 != "-noverifyfiles" } + ["-silent"]
        try wine.spawn(args, cwd: paths.steam)
        let start = Date()
        var lastLaunch = Date()
        var relaunches = 0
        var notRunningSince: Date?
        var stage = 0
        var lastTotal = 0
        var readySince: Date?
        var lastLogSize = -1
        var lastLogChange = Date()
        while true {
            try await Task.sleep(nanoseconds: 1_000_000_000)
            let log = (try? String(contentsOf: paths.steamBootstrapLog, encoding: .utf8)) ?? ""
            if log.utf8.count != lastLogSize { lastLogSize = log.utf8.count; lastLogChange = Date() }
            if let m = Self.lastDownloadProgress(in: log) {
                // A new total means the updater moved on to its next package.
                if lastTotal != 0 && m.total != lastTotal { stage += 1 }
                lastTotal = m.total
                // Two download stages (win32 bootstrapper, then win64 client): split the bar.
                let stageFraction = Double(m.done) / Double(max(m.total, 1))
                let base = min(Double(stage), 1) * 0.5
                progress(min(0.98, base + stageFraction * 0.5), m.done, m.total)
            }
            let running = isSteamRunning()
            if isBootstrapped && running {
                if readySince == nil { readySince = Date() }
                if Date().timeIntervalSince(readySince!) > 8 { break }
            }
            // Watchdog: the updater sometimes hangs (e.g. "Checking for available updates…").
            // If its log hasn't moved for two minutes, close it and start it again.
            if running && !isBootstrapped && Date().timeIntervalSince(lastLogChange) > 120
                && Date().timeIntervalSince(lastLaunch) > 120 {
                guard relaunches < 4 else { throw SteamError.bootstrapTimeout }
                relaunches += 1
                wine.appendLog("Steam bootstrap: stalled for 2 minutes, restarting it (\(relaunches))")
                onStall()
                await wine.killAll()
                try await Task.sleep(nanoseconds: 2_000_000_000)
                lastLaunch = Date()
                lastLogChange = Date()
                try wine.spawn(args, cwd: paths.steam)
                continue
            }
            if running { notRunningSince = nil } else if notRunningSince == nil { notRunningSince = Date() }
            if !running, let since = notRunningSince, Date().timeIntervalSince(since) > 20,
               Date().timeIntervalSince(lastLaunch) > 25 {
                // The updater sometimes exits between stages; start it again.
                guard relaunches < 4 else { throw SteamError.bootstrapTimeout }
                relaunches += 1
                wine.appendLog("Steam bootstrap: relaunching (\(relaunches))")
                lastLaunch = Date()
                try wine.spawn(args, cwd: paths.steam)
            }
            if Date().timeIntervalSince(start) > 1800 { throw SteamError.bootstrapTimeout }
        }
        progress(1, 0, 0)
        try await shutdown()
        patchWebhelper()
        try await installService()
    }

    /// Last "(12,345 of 336,229 KB)" in the bootstrap log, whatever the language
    /// ("Downloading update (… of … KB)", "Descargando actualización (… de … KB)"…).
    static func lastDownloadProgress(in log: String) -> (done: Int, total: Int)? {
        let tail = String(log.suffix(4000))
        guard let re = try? NSRegularExpression(pattern: #"\(([0-9][0-9.,\u00a0 ]*) \S+ ([0-9][0-9.,\u00a0 ]*) KB\)"#) else { return nil }
        let ns = tail as NSString
        guard let m = re.matches(in: tail, range: NSRange(location: 0, length: ns.length)).last else { return nil }
        func num(_ r: NSRange) -> Int? {
            Int(ns.substring(with: r).filter(\.isNumber))
        }
        guard let a = num(m.range(at: 1)), let b = num(m.range(at: 2)), b > 0 else { return nil }
        return (a, b)
    }

    /// Steam asks to "install the Steam service" otherwise.
    func installService() async throws {
        guard FileManager.default.fileExists(atPath: paths.steamService.path) else { return }
        try await wine.run([paths.steamService.path, "/install"], timeout: 120)
    }

    // MARK: web helper wrapper

    /// Any version of our wrapper (current or older builds): tiny, or carrying our marker.
    static func isWrapper(_ data: Data) -> Bool {
        data.count < 1_000_000 || data.range(of: Data("CIDER_STEAMWEBHELPER_WRAPPER".utf8)) != nil
    }

    enum WebhelperState { case patched, applied, notInstalled, realMissing }

    /// Puts our wrapper in front of steamwebhelper.exe. Steam's CEF paints black under Wine
    /// on macOS unless it runs single-process without GPU. Re-applied before every start
    /// because Steam updates overwrite it. A wrapper is never moved over the real binary.
    @discardableResult
    func patchWebhelper() -> WebhelperState {
        let fm = FileManager.default
        let dir = paths.steamWebhelperDir
        let helper = dir.appendingPathComponent("steamwebhelper.exe")
        let real = dir.appendingPathComponent("steamwebhelper_real.exe")
        guard let wrapper = try? Data(contentsOf: paths.webhelperWrapper),
              let current = try? Data(contentsOf: helper) else { return .notInstalled }
        let realData = try? Data(contentsOf: real, options: .alwaysMapped)
        let realOK = realData.map { !Self.isWrapper($0) } ?? false
        do {
            if Self.isWrapper(current) {
                // Already wrapped (maybe by an older Cider): only refresh the wrapper itself.
                guard realOK else { return .realMissing }
                if current != wrapper { try wrapper.write(to: helper) }
                return .patched
            }
            // Steam put a fresh real helper in place: keep it as _real and wrap it.
            try? fm.removeItem(at: real)
            try fm.moveItem(at: helper, to: real)
            try wrapper.write(to: helper)
            wine.appendLog("steamwebhelper wrapper applied")
            return .applied
        } catch {
            wine.appendLog("steamwebhelper wrapper failed: \(error)")
            return .notInstalled
        }
    }

    var isWebhelperPatched: Bool {
        let dir = paths.steamWebhelperDir
        guard let a = try? Data(contentsOf: dir.appendingPathComponent("steamwebhelper.exe")),
              let r = try? Data(contentsOf: dir.appendingPathComponent("steamwebhelper_real.exe"), options: .alwaysMapped)
        else { return false }
        return Self.isWrapper(a) && !Self.isWrapper(r)
    }

    /// If the real web helper got lost, let Steam restore it (verification on), then wrap it.
    func repairWebhelperIfNeeded(language: String) async throws {
        guard patchWebhelper() == .realMissing else { return }
        wine.appendLog("steamwebhelper_real.exe is missing: asking Steam to restore it")
        await wine.killAll()
        let dir = paths.steamWebhelperDir
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("steamwebhelper.exe"))
        try? FileManager.default.removeItem(at: dir.appendingPathComponent("steamwebhelper_real.exe"))
        let args = [paths.steamExe.path] + baseArguments(language: language).filter { $0 != "-noverifyfiles" } + ["-silent"]
        try wine.spawn(args, cwd: paths.steam)
        let start = Date()
        let helper = dir.appendingPathComponent("steamwebhelper.exe")
        while Date().timeIntervalSince(start) < 600 {
            try await Task.sleep(nanoseconds: 2_000_000_000)
            if let size = (try? FileManager.default.attributesOfItem(atPath: helper.path))?[.size] as? Int, size > 1_000_000 {
                try await Task.sleep(nanoseconds: 8_000_000_000)
                break
            }
        }
        await wine.killAll()
        patchWebhelper()
    }

    // MARK: start / stop

    func baseArguments(language: String) -> [String] {
        ["-noverifyfiles", "-cef-disable-gpu", "-cef-disable-gpu-compositing", "-cef-disable-d3d11",
         "-cef-disable-sandbox", "-nofriendsui", "-language", language]
    }

    /// Starts Steam (inside Cider's virtual desktop when `session.desktop` is set).
    func start(session: SteamSession, language: String, extra: [String] = []) async throws {
        try await repairWebhelperIfNeeded(language: language)
        // Leftovers from a Steam that died (no steam.exe, helpers still around) would block the new one.
        if !isSteamRunning() && !processes().isEmpty { await wine.killAll() }
        patchWebhelper()
        // Reset ActiveUser: a value left by a Steam that was killed would look like a live session.
        try? await wine.importRegistry("""
        [HKEY_CURRENT_USER\\Software\\Valve\\Steam]
        "Language"="\(language)"

        [HKEY_CURRENT_USER\\Software\\Valve\\Steam\\ActiveProcess]
        "ActiveUser"=dword:00000000
        """)
        var opts = WineEnvironment.Options()
        opts.fpsHUD = session.fpsHUD
        opts.msync = session.msync
        opts.resizableWindows = session.resizable ?? true
        opts.renderScale = session.renderScale
        var args: [String] = []
        if let desktop = session.desktop {
            args = ["explorer", "/desktop=Cider,\(desktop)"]
        }
        args += [paths.steamExe.path] + baseArguments(language: language) + extra
        try wine.spawn(args, options: opts, cwd: paths.steam)
    }

    /// Sends a command (e.g. `-applaunch 123`, `steam://open/store`) to the running Steam.
    func send(_ args: [String], language: String) throws {
        // Only ever forward to a running Steam: a bare `steam.exe <uri>` would start a Steam
        // without our flags, desktop and -noverifyfiles.
        try wine.spawn([paths.steamExe.path, "-noverifyfiles"] + args, cwd: paths.steam)
    }

    /// Asks Steam to quit and waits; kills the prefix if it doesn't.
    func shutdown(timeout: TimeInterval = 25) async throws {
        if isSteamRunning() {
            try? wine.spawn([paths.steamExe.path, "-shutdown"], cwd: paths.steam)
            let start = Date()
            while isSteamRunning() && Date().timeIntervalSince(start) < timeout {
                try await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
        await wine.killAll()
    }
}

final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    let progress: @Sendable (Double) -> Void
    init(progress: @escaping @Sendable (Double) -> Void) { self.progress = progress }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {}
}
