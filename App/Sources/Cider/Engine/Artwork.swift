import AppKit
import Foundation

/// Steam artwork from Valve's public CDN, cached on disk.
actor ArtworkStore {
    static let shared = ArtworkStore()

    enum Kind: String, Sendable {
        case cover, hero, logo, header

        /// Candidate file names, best first.
        var files: [String] {
            switch self {
            case .cover: return ["library_600x900_2x.jpg", "library_600x900.jpg"]
            case .hero: return ["library_hero.jpg"]
            case .logo: return ["logo.png"]
            case .header: return ["header.jpg"]
            }
        }
    }

    private let memory = NSCache<NSString, NSImage>()
    private var inFlight: [String: Task<NSImage?, Never>] = [:]
    private let dir = CiderPaths.shared.artworkCache

    func image(appID: Int, kind: Kind) async -> NSImage? {
        guard appID > 0 else { return nil }
        let key = "\(appID)-\(kind.rawValue)"
        if let img = memory.object(forKey: key as NSString) { return img }
        if let t = inFlight[key] { return await t.value }
        let dir = self.dir
        let t = Task<NSImage?, Never> {
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let local = dir.appendingPathComponent(key)
            if let img = NSImage(contentsOf: local) { return img }
            let marker = local.path + ".missing"
            if let attrs = try? FileManager.default.attributesOfItem(atPath: marker),
               let date = attrs[.modificationDate] as? Date, Date().timeIntervalSince(date) < 86_400 { return nil }
            // Steam's own cache in the prefix has art the public CDN sometimes lacks.
            let steamCache = CiderPaths.shared.steam.appendingPathComponent("appcache/librarycache/\(appID)")
            for file in kind.files {
                let url = steamCache.appendingPathComponent(file)
                if let data = try? Data(contentsOf: url), let img = NSImage(data: data) {
                    try? data.write(to: local)
                    return img
                }
            }
            var onlyNotFound = true
            for file in kind.files {
                for host in ["https://cdn.cloudflare.steamstatic.com/steam/apps",
                             "https://shared.cloudflare.steamstatic.com/store_item_assets/steam/apps"] {
                    guard let url = URL(string: "\(host)/\(appID)/\(file)") else { continue }
                    var req = URLRequest(url: url)
                    req.timeoutInterval = 20
                    guard let (data, resp) = try? await URLSession.shared.data(for: req) else { onlyNotFound = false; continue }
                    guard (resp as? HTTPURLResponse)?.statusCode == 200, let img = NSImage(data: data) else { continue }
                    try? data.write(to: local)
                    return img
                }
            }
            if onlyNotFound { FileManager.default.createFile(atPath: marker, contents: nil) }
            return nil
        }
        inFlight[key] = t
        let img = await t.value
        inFlight[key] = nil
        if let img { memory.setObject(img, forKey: key as NSString) }
        return img
    }
}
