import Foundation

/// Reads the games installed in Cider's Steam (libraryfolders.vdf + appmanifest_*.acf).
struct SteamLibrary: Sendable {
    let paths: CiderPaths

    /// Steam tools and runtimes that aren't games.
    static let hiddenAppIDs: Set<Int> = [228980, 1070560, 1391110, 1628350, 1493710, 2180100, 2348590, 961940, 1826330]

    func libraryFolders() -> [URL] {
        var folders: [URL] = [paths.steam]
        if let vdf = VDF.parse(contentsOf: paths.steam.appendingPathComponent("steamapps/libraryfolders.vdf")),
           let root = vdf["libraryfolders"] {
            for (_, entry) in root.children {
                if let p = entry["path"]?.string, let url = paths.unixPath(forWindowsPath: p) {
                    folders.append(url)
                }
            }
        }
        var seen = Set<String>()
        return folders.filter { seen.insert($0.standardizedFileURL.resolvingSymlinksInPath().path).inserted }
    }

    func games() -> [Game] {
        let playtimes = steamPlaytimes()
        var result: [Game] = []
        let fm = FileManager.default
        for folder in libraryFolders() {
            let steamapps = folder.appendingPathComponent("steamapps", isDirectory: true)
            guard let files = try? fm.contentsOfDirectory(atPath: steamapps.path) else { continue }
            for f in files where f.hasPrefix("appmanifest_") && f.hasSuffix(".acf") {
                guard let vdf = VDF.parse(contentsOf: steamapps.appendingPathComponent(f)),
                      let state = vdf["AppState"],
                      let appID = state["appid"]?.int,
                      !Self.hiddenAppIDs.contains(appID) else { continue }
                let name = state["name"]?.string ?? "App \(appID)"
                let lower = name.lowercased()
                if lower.contains("redistributable") || lower.hasPrefix("proton") || lower.contains("steam linux runtime")
                    || lower.contains("steamworks") { continue }
                let dir = steamapps.appendingPathComponent("common/\(state["installdir"]?.string ?? "")", isDirectory: true)
                var game = Game(appID: appID, name: name, installDir: dir,
                                sizeOnDisk: Int64(state["SizeOnDisk"]?.string ?? "") ?? 0,
                                stateFlags: state["StateFlags"]?.int ?? 0)
                if let lp = state["LastPlayed"]?.int, lp > 0 { game.lastPlayed = Date(timeIntervalSince1970: TimeInterval(lp)) }
                if let pt = playtimes[appID] {
                    game.playtimeMinutes = pt.minutes
                    if let l = pt.last, l > (game.lastPlayed ?? .distantPast) { game.lastPlayed = l }
                }
                result.append(game)
            }
        }
        return result.sorted { $0.sortName < $1.sortName }
    }

    /// Playtime and last-played date that Steam keeps per user in localconfig.vdf.
    func steamPlaytimes() -> [Int: (minutes: Int, last: Date?)] {
        let userdata = paths.steam.appendingPathComponent("userdata", isDirectory: true)
        guard let users = try? FileManager.default.contentsOfDirectory(atPath: userdata.path) else { return [:] }
        var out: [Int: (Int, Date?)] = [:]
        for u in users {
            let url = userdata.appendingPathComponent("\(u)/config/localconfig.vdf")
            guard let vdf = VDF.parse(contentsOf: url),
                  let apps = vdf.at("UserLocalConfigStore", "Software", "Valve", "Steam", "apps") else { continue }
            for (id, app) in apps.children {
                guard let appID = Int(id) else { continue }
                let minutes = app["Playtime"]?.int ?? 0
                let last = app["LastPlayed"]?.int.flatMap { $0 > 0 ? Date(timeIntervalSince1970: TimeInterval($0)) : nil }
                if minutes > 0 || last != nil {
                    let prev = out[appID]
                    out[appID] = (max(minutes, prev?.0 ?? 0), [last, prev?.1].compactMap { $0 }.max())
                }
            }
        }
        return out
    }
}

/// Detects which graphics API a game uses by looking at the DLL names its executables import.
enum GraphicsProbe {
    static let ignoredExecutables = ["unins", "crash", "redist", "setup", "vcredist", "dxsetup", "dotnet",
                                     "uninstall", "report", "easyanticheat", "battleye", "launcherpatcher", "cefprocess"]

    static func executables(in dir: URL, maxDepth: Int = 4) -> [URL] {
        let fm = FileManager.default
        guard let e = fm.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
                                    options: [.skipsHiddenFiles]) else { return [] }
        var out: [URL] = []
        for case let url as URL in e {
            if e.level > maxDepth { e.skipDescendants(); continue }
            if url.pathExtension.lowercased() == "exe" { out.append(url) }
        }
        return out
    }

    static func probe(gameDir: URL) -> GraphicsInfo? {
        let exes = executables(in: gameDir).filter { exe in
            let n = exe.lastPathComponent.lowercased()
            return !ignoredExecutables.contains { n.contains($0) }
        }
        // Largest executable is almost always the game itself.
        let sized = exes.map { ($0, (try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
            .sorted { $0.1 > $1.1 }
        var candidates = sized.prefix(4).map(\.0)
        // Unity games keep their renderer in UnityPlayer.dll next to a tiny launcher .exe.
        if let unity = exes.first.map({ $0.deletingLastPathComponent().appendingPathComponent("UnityPlayer.dll") }),
           FileManager.default.fileExists(atPath: unity.path) { candidates.append(unity) }
        var best: GraphicsInfo?
        for exe in candidates {
            guard let info = inspect(exe) else { continue }
            if best == nil || rank(info.api) > rank(best!.api) { best = info }
        }
        return best
    }

    private static func rank(_ api: GraphicsAPI) -> Int {
        switch api {
        case .dx11: return 7
        case .dx10: return 6
        case .dx9: return 5
        case .dx8: return 4
        case .vulkan: return 3
        case .openGL: return 2
        case .dx12: return 1
        case .unknown: return 0
        }
    }

    static func inspect(_ exe: URL) -> GraphicsInfo? {
        guard let h = try? FileHandle(forReadingFrom: exe) else { return nil }
        defer { try? h.close() }
        guard let data = try? h.read(upToCount: 96 * 1024 * 1024), data.count > 0x40 else { return nil }
        // PE header: machine type tells 32 vs 64 bit.
        let peOffset = Int(data[0x3C]) | Int(data[0x3D]) << 8 | Int(data[0x3E]) << 16 | Int(data[0x3F]) << 24
        var is64 = true
        if peOffset > 0, peOffset + 6 < data.count {
            let machine = Int(data[peOffset + 4]) | Int(data[peOffset + 5]) << 8
            is64 = machine == 0x8664 || machine == 0xAA64
        }
        func has(_ s: String) -> Bool {
            data.range(of: Data(s.utf8)) != nil || data.range(of: Data(s.uppercased().utf8)) != nil
        }
        let api: GraphicsAPI
        if has("d3d11.dll") { api = .dx11 }
        else if has("d3d10.dll") || has("d3d10_1.dll") || has("d3d10core.dll") { api = .dx10 }
        else if has("d3d9.dll") { api = .dx9 }
        else if has("d3d8.dll") { api = .dx8 }
        else if has("vulkan-1.dll") { api = .vulkan }
        else if has("d3d12.dll") { api = .dx12 }
        else if has("opengl32.dll") || has("OPENGL32.dll") { api = .openGL }
        else { api = .unknown }
        return GraphicsInfo(api: api, is64Bit: is64, executable: exe.lastPathComponent)
    }
}
