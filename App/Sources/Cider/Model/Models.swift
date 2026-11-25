import Foundation

/// A Steam game installed in Cider's prefix.
struct Game: Identifiable, Hashable, Sendable {
    let appID: Int
    var name: String
    var installDir: URL
    var sizeOnDisk: Int64
    var stateFlags: Int
    var lastPlayed: Date?
    var playtimeMinutes: Int?
    /// Games added from outside Steam: the executable to run.
    var customExe: URL? = nil
    /// Steam app whose artwork / store page represents this game (custom games).
    var artworkAppID: Int? = nil

    var id: Int { appID }
    var isCustom: Bool { customExe != nil }
    /// App id used to fetch artwork (none for custom games without a Steam match).
    var artID: Int { isCustom ? (artworkAppID ?? 0) : appID }

    var isInstalled: Bool { isCustom || stateFlags & 4 != 0 }
    /// Update required / running / downloading / staging / committing...
    var isUpdating: Bool {
        stateFlags & (2 | 256 | 512 | 1024 | 1_048_576 | 2_097_152 | 4_194_304) != 0
    }

    var sortName: String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: "the ", with: "", options: .anchored)
    }
}

/// A game added from outside Steam (any Windows .exe).
struct CustomGame: Codable, Hashable, Sendable, Identifiable {
    var id = UUID()
    var name: String
    /// Unix path of the executable.
    var exePath: String
    var artworkAppID: Int?
    var sizeBytes: Int64 = 0
    var addedAt = Date()

    /// Stable negative number so custom games never clash with Steam app ids.
    var numericID: Int {
        let b = id.uuid
        let v = Int(b.0) << 24 | Int(b.1) << 16 | Int(b.2) << 8 | Int(b.3)
        return -(v % 2_000_000_000 + 1)
    }

    var exeURL: URL { URL(fileURLWithPath: exePath) }

    var asGame: Game {
        Game(appID: numericID, name: name, installDir: exeURL.deletingLastPathComponent(), sizeOnDisk: sizeBytes,
             stateFlags: 4, customExe: exeURL, artworkAppID: artworkAppID)
    }
}

/// Graphics API a game uses, detected from its executables.
enum GraphicsAPI: String, Codable, Sendable {
    case dx12, dx11, dx10, dx9, dx8, openGL, vulkan, unknown
}

struct GraphicsInfo: Codable, Hashable, Sendable {
    var api: GraphicsAPI
    var is64Bit: Bool
    var executable: String
}

/// Per-game settings (anything nil falls back to the global defaults).
struct GameSettings: Codable, Hashable, Sendable {
    var display: DisplayMode?
    var fpsHUD: Bool?
    var msync: Bool?
    var extraArguments: String = ""
    /// For games with a known anti-cheat-free executable: launch it directly (default on).
    var skipAntiCheat: Bool?
    /// For games whose window mode Cider knows how to set: open windowed (default on).
    var windowed: Bool?
    /// Render-resolution divisor (1.5 = 67 %, 2 = 50 %): Windows sees a smaller screen and
    /// macOS scales the game up (nil or 1 = native).
    var renderScale: Double?
}

enum DisplayMode: Codable, Hashable, Sendable {
    /// Each game window is a normal macOS window (resizable, full screen button…).
    case native
    /// A fixed-size Wine virtual desktop that contains Steam and the game.
    case window(width: Int, height: Int)
    /// Older name of `native`, kept so saved settings still decode.
    case fullscreen

    static let presets: [DisplayMode] = [
        .native,
        .window(width: 1280, height: 720),
        .window(width: 1600, height: 900),
        .window(width: 1920, height: 1080),
        .window(width: 2560, height: 1440),
    ]

    /// Value for `explorer /desktop=Cider,<WxH>`, nil when no virtual desktop is used.
    var desktopSize: String? {
        switch self {
        case .window(let w, let h): return "\(w)x\(h)"
        case .native, .fullscreen: return nil
        }
    }

    var normalized: DisplayMode { self == .fullscreen ? .native : self }
}

struct PlayStats: Codable, Hashable, Sendable {
    var lastPlayed: Date?
    var totalSeconds: Double = 0
}

enum SteamLanguage: String, Codable, CaseIterable, Sendable {
    case automatic, spanish, english, latam, french, german, italian, portuguese, brazilian

    var steamName: String {
        switch self {
        case .automatic:
            let lang = Locale.preferredLanguages.first?.prefix(2) ?? "es"
            switch lang {
            case "es": return "spanish"
            case "fr": return "french"
            case "de": return "german"
            case "it": return "italian"
            case "pt": return "portuguese"
            default: return "english"
            }
        default: return rawValue
        }
    }
}

struct AppSettings: Codable, Hashable, Sendable {
    var defaultDisplay: DisplayMode = .native
    /// macOS window controls on game windows (nil = on).
    var resizableWindows: Bool?
    var fpsHUD = false
    var msync = true
    var steamLanguage: SteamLanguage = .automatic
    var keepSteamOpen = true
    /// Hide Cider while a game runs (it comes back when the game closes). nil = on.
    var hideWhilePlaying: Bool?
}

/// Everything Cider persists between launches (in `state.json`).
struct PersistentState: Codable, Sendable {
    var onboardingComplete = false
    var settings = AppSettings()
    var games: [String: GameSettings] = [:]
    var stats: [String: PlayStats] = [:]
    var graphics: [String: GraphicsInfo] = [:]
    var lastSession: SteamSession?
    var settingsVersion: Int?
    var customGames: [CustomGame]?

    static func load(from url: URL) -> PersistentState {
        guard let data = try? Data(contentsOf: url) else { return PersistentState() }
        let dec = JSONDecoder()
        dec.dateDecodingStrategy = .iso8601
        var state = (try? dec.decode(PersistentState.self, from: data)) ?? PersistentState()
        if (state.settingsVersion ?? 1) < 2 {
            // v2: games open in normal macOS windows by default instead of a fixed virtual desktop.
            state.settings.defaultDisplay = .native
            state.settingsVersion = 2
        }
        return state
    }

    func save(to url: URL) {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        enc.dateEncodingStrategy = .iso8601
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? enc.encode(self).write(to: url, options: .atomic)
    }
}

/// What the running Steam was started with. Games inherit Steam's virtual desktop and
/// environment, so a game that needs different values requires restarting Steam.
struct SteamSession: Codable, Hashable, Sendable {
    var desktop: String?
    var fpsHUD: Bool
    var msync: Bool
    var resizable: Bool?
    var renderScale: Double?
}
