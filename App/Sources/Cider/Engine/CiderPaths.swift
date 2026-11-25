import Foundation

/// Every location Cider reads or writes.
struct CiderPaths: Sendable {
    /// Bundled Windows runtime (Wine + DXMT + Steam web helper wrapper).
    let runtime: URL
    /// User data: prefix, logs, caches, state.
    let data: URL

    static let shared = CiderPaths()

    init() {
        let env = ProcessInfo.processInfo.environment
        if let r = env["CIDER_RUNTIME"], !r.isEmpty {
            runtime = URL(fileURLWithPath: r, isDirectory: true)
        } else {
            runtime = Bundle.main.resourceURL!.appendingPathComponent("runtime", isDirectory: true)
        }
        if let d = env["CIDER_DATA_DIR"], !d.isEmpty {
            data = URL(fileURLWithPath: d, isDirectory: true)
        } else {
            data = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Cider", isDirectory: true)
        }
    }

    var wineRoot: URL { runtime.appendingPathComponent("wine", isDirectory: true) }
    var wine: URL { wineRoot.appendingPathComponent("bin/wine") }
    var wineserver: URL { wineRoot.appendingPathComponent("bin/wineserver") }
    var webhelperWrapper: URL { runtime.appendingPathComponent("steamwebhelper.exe") }
    var licenses: URL { runtime.appendingPathComponent("licenses", isDirectory: true) }
    var winemetalDLL: URL { wineRoot.appendingPathComponent("lib/wine/x86_64-windows/winemetal.dll") }

    var prefix: URL { data.appendingPathComponent("prefix", isDirectory: true) }
    var logs: URL { data.appendingPathComponent("logs", isDirectory: true) }
    var downloads: URL { data.appendingPathComponent("downloads", isDirectory: true) }
    var artworkCache: URL { data.appendingPathComponent("cache/artwork", isDirectory: true) }
    var stateFile: URL { data.appendingPathComponent("state.json") }
    var wineLog: URL { logs.appendingPathComponent("wine.log") }

    var driveC: URL { prefix.appendingPathComponent("drive_c", isDirectory: true) }
    var system32: URL { driveC.appendingPathComponent("windows/system32", isDirectory: true) }
    var steam: URL { driveC.appendingPathComponent("Program Files (x86)/Steam", isDirectory: true) }
    var steamExe: URL { steam.appendingPathComponent("steam.exe") }
    var steamWebhelperDir: URL { steam.appendingPathComponent("bin/cef/cef.win64", isDirectory: true) }
    var steamBootstrapLog: URL { steam.appendingPathComponent("logs/bootstrap_log.txt") }
    var steamService: URL { steam.appendingPathComponent("bin/SteamService.exe") }

    var runtimeIsPresent: Bool { FileManager.default.isExecutableFile(atPath: wine.path) }
    var prefixExists: Bool { FileManager.default.fileExists(atPath: prefix.appendingPathComponent("system.reg").path) }

    func ensureDirectories() {
        for d in [data, logs, downloads, artworkCache] {
            try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        }
    }

    /// Maps a Windows path ("C:\\Program Files (x86)\\Steam") to its location inside the prefix.
    func unixPath(forWindowsPath win: String) -> URL? {
        let p = win.replacingOccurrences(of: "\\\\", with: "\\")
        guard p.count >= 2, p.dropFirst().first == ":" else { return nil }
        let drive = p.prefix(1).lowercased()
        let rest = p.dropFirst(2).replacingOccurrences(of: "\\", with: "/")
        let base = prefix.appendingPathComponent("dosdevices/\(drive):", isDirectory: true).resolvingSymlinksInPath()
        let trimmed = rest.hasPrefix("/") ? String(rest.dropFirst()) : rest
        return trimmed.isEmpty ? base : base.appendingPathComponent(trimmed)
    }
}
