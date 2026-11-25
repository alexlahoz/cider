import Foundation

/// Sets the window mode of games whose settings files Cider understands, right before launch.
/// Windowed games get the macOS window controls (resize, full screen…) from our winemac patch,
/// whereas "borderless full screen" windows have no title bar to put them on.
enum GameWindowConfig {
    static func isSupported(_ appID: Int) -> Bool { [459220, 976730].contains(appID) }

    enum Engine: String, Sendable { case unity, unreal, source, unknown }

    /// Detects the game engine from the files in the install folder.
    static func engine(of dir: URL) -> Engine {
        let fm = FileManager.default
        func exists(_ rel: String) -> Bool { fm.fileExists(atPath: dir.appendingPathComponent(rel).path) }
        if exists("UnityPlayer.dll") { return .unity }
        let top = (try? fm.contentsOfDirectory(atPath: dir.path)) ?? []
        if top.contains(where: { $0.hasSuffix("_Data") }) && top.contains(where: { $0.lowercased().hasSuffix(".exe") }) {
            if top.contains(where: { exists("\($0)/globalgamemanagers") || exists("\($0)/data.unity3d") }) { return .unity }
        }
        if exists("Engine/Binaries") || exists("Engine/Build") { return .unreal }
        if exists("bin/engine.dll") || exists("hl2.exe") || exists("bin/win64/engine2.dll") { return .source }
        return .unknown
    }

    /// Command-line arguments that ask a game engine to start windowed.
    static func windowedArguments(for engine: Engine) -> [String] {
        switch engine {
        case .unity: return ["-screen-fullscreen", "0", "-window-mode", "windowed"]
        case .unreal, .source: return ["-windowed"]
        case .unknown: return []
        }
    }

    static func apply(appID: Int, windowed: Bool, prefix paths: CiderPaths) {
        let user = NSUserName()
        let base = paths.driveC.appendingPathComponent("users/\(user)/AppData", isDirectory: true)
        switch appID {
        case 459220: haloWars(base.appendingPathComponent("Local/Halo Wars/GameConfig.dat"), windowed: windowed)
        case 976730: unrealIni(base.appendingPathComponent("LocalLow/MCC/Saved/Config/WindowsNoEditor/GameUserSettings.ini"),
                               windowed: windowed)
        default: break
        }
    }

    /// Halo Wars: Definitive Edition — 48-byte GameConfig.dat. Byte 0x13: 0 = windowed, 1 = full screen.
    /// Bytes 0x28/0x2C: window width/height (UInt32 LE).
    static func haloWars(_ url: URL, windowed: Bool) {
        guard var data = try? Data(contentsOf: url), data.count >= 0x30 else { return }
        data[0x13] = windowed ? 0 : 1
        if windowed {
            let w = data.subdata(in: 0x28..<0x2C).withUnsafeBytes { $0.load(as: UInt32.self) }
            let h = data.subdata(in: 0x2C..<0x30).withUnsafeBytes { $0.load(as: UInt32.self) }
            if w < 640 || h < 400 || w > 1400 {
                var nw = UInt32(1280).littleEndian, nh = UInt32(720).littleEndian
                data.replaceSubrange(0x28..<0x2C, with: Data(bytes: &nw, count: 4))
                data.replaceSubrange(0x2C..<0x30, with: Data(bytes: &nh, count: 4))
            }
        }
        try? data.write(to: url)
    }

    /// Unreal Engine GameUserSettings.ini — FullscreenMode: 0 full screen, 1 borderless, 2 windowed.
    static func unrealIni(_ url: URL, windowed: Bool) {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
        let mode = windowed ? "2" : "1"
        var lines = text.components(separatedBy: "\n")
        for (i, line) in lines.enumerated() {
            for key in ["FullscreenMode", "LastConfirmedFullscreenMode", "PreferredFullscreenMode"]
            where line.hasPrefix(key + "=") {
                lines[i] = key + "=" + mode + (line.hasSuffix("\r") ? "\r" : "")
            }
        }
        try? lines.joined(separator: "\n").write(to: url, atomically: true, encoding: .utf8)
    }
}
