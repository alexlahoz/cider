import AppKit
import CoreImage
import Foundation

/// Public store data for a game (description, genres, screenshots…), from Steam's store API.
struct StoreDetails: Codable, Sendable, Hashable {
    var shortDescription: String
    var genres: [String]
    var developers: [String]
    var publishers: [String]
    var releaseDate: String
    var metacritic: Int?
    var controllerSupport: String?
    var screenshots: [Screenshot]
    var categories: [String]

    struct Screenshot: Codable, Sendable, Hashable, Identifiable {
        var id: Int
        var thumbnail: URL
        var full: URL
    }
}

actor StoreInfoStore {
    static let shared = StoreInfoStore()

    private var memory: [Int: StoreDetails] = [:]
    private let dir = CiderPaths.shared.artworkCache.deletingLastPathComponent().appendingPathComponent("store", isDirectory: true)

    func details(appID: Int) async -> StoreDetails? {
        guard appID > 0 else { return nil }
        if let d = memory[appID] { return d }
        let file = dir.appendingPathComponent("\(appID)-\(Self.language).json")
        if let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
           let date = attrs[.modificationDate] as? Date, Date().timeIntervalSince(date) < 7 * 86_400,
           let data = try? Data(contentsOf: file), let d = try? JSONDecoder().decode(StoreDetails.self, from: data) {
            memory[appID] = d
            return d
        }
        guard let url = URL(string: "https://store.steampowered.com/api/appdetails?appids=\(appID)&l=\(Self.language)"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let entry = root[String(appID)] as? [String: Any], entry["success"] as? Bool == true,
              let d = entry["data"] as? [String: Any] else {
            if let data = try? Data(contentsOf: file), let d = try? JSONDecoder().decode(StoreDetails.self, from: data) { return d }
            return nil
        }
        func names(_ key: String) -> [String] {
            (d[key] as? [[String: Any]])?.compactMap { $0["description"] as? String } ?? []
        }
        let shots = (d["screenshots"] as? [[String: Any]] ?? []).compactMap { s -> StoreDetails.Screenshot? in
            guard let id = s["id"] as? Int,
                  let t = (s["path_thumbnail"] as? String).flatMap(URL.init(string:)),
                  let f = (s["path_full"] as? String).flatMap(URL.init(string:)) else { return nil }
            return .init(id: id, thumbnail: t, full: f)
        }
        let details = StoreDetails(
            shortDescription: Self.plain(d["short_description"] as? String ?? ""),
            genres: names("genres"),
            developers: d["developers"] as? [String] ?? [],
            publishers: d["publishers"] as? [String] ?? [],
            releaseDate: (d["release_date"] as? [String: Any])?["date"] as? String ?? "",
            metacritic: (d["metacritic"] as? [String: Any])?["score"] as? Int,
            controllerSupport: d["controller_support"] as? String,
            screenshots: Array(shots.prefix(12)),
            categories: names("categories"))
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? JSONEncoder().encode(details).write(to: file)
        memory[appID] = details
        return details
    }

    static var language: String {
        (Locale.preferredLanguages.first ?? "es").hasPrefix("es") ? "spanish" : "english"
    }

    static func plain(_ html: String) -> String {
        html.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&#39;", with: "'")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Remote image loader with an in-memory cache (screenshots).
actor RemoteImageCache {
    static let shared = RemoteImageCache()
    private let cache = NSCache<NSURL, NSImage>()

    func image(_ url: URL) async -> NSImage? {
        if let i = cache.object(forKey: url as NSURL) { return i }
        guard let (data, _) = try? await URLSession.shared.data(from: url), let img = NSImage(data: data) else { return nil }
        cache.setObject(img, forKey: url as NSURL)
        return img
    }
}

/// Dominant ambient colour of a piece of art, used to tint the window behind it.
enum AmbientColor {
    private static let context = CIContext(options: [.workingColorSpace: NSNull()])
    private static var cache: [Int: NSColor] = [:]
    private static let lock = NSLock()

    static func color(for image: NSImage, key: Int) -> NSColor? {
        lock.lock(); if let c = cache[key] { lock.unlock(); return c }; lock.unlock()
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let ci = CIImage(cgImage: cg)
        guard let filter = CIFilter(name: "CIAreaAverage", parameters: [kCIInputImageKey: ci, kCIInputExtentKey: CIVector(cgRect: ci.extent)]),
              let out = filter.outputImage else { return nil }
        var px = [UInt8](repeating: 0, count: 4)
        context.render(out, toBitmap: &px, rowBytes: 4, bounds: CGRect(x: 0, y: 0, width: 1, height: 1), format: .RGBA8, colorSpace: nil)
        var h: CGFloat = 0, s: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        NSColor(red: CGFloat(px[0]) / 255, green: CGFloat(px[1]) / 255, blue: CGFloat(px[2]) / 255, alpha: 1)
            .usingColorSpace(.deviceRGB)?.getHue(&h, saturation: &s, brightness: &b, alpha: &a)
        // Keep the hue, make it rich but dark enough to sit behind white text.
        let c = NSColor(hue: h, saturation: min(1, max(0.35, s * 1.6)), brightness: min(0.55, max(0.32, b)), alpha: 1)
        lock.lock(); cache[key] = c; lock.unlock()
        return c
    }
}

/// Finds the Steam app that matches a game name (to borrow its artwork and description).
enum StoreSearch {
    static func bestMatch(for name: String) async -> Int? {
        var comps = URLComponents(string: "https://store.steampowered.com/api/storesearch/")!
        comps.queryItems = [.init(name: "term", value: name), .init(name: "l", value: "spanish"), .init(name: "cc", value: "ES")]
        guard let url = comps.url, let (data, _) = try? await URLSession.shared.data(from: url),
              let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let items = root["items"] as? [[String: Any]], !items.isEmpty else { return nil }
        func norm(_ s: String) -> String {
            s.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
                .components(separatedBy: CharacterSet.alphanumerics.inverted).joined()
        }
        let target = norm(name)
        let candidates = items.compactMap { item -> (Int, String)? in
            guard let id = item["id"] as? Int, let n = item["name"] as? String else { return nil }
            return (id, norm(n))
        }
        if let exact = candidates.first(where: { $0.1 == target }) { return exact.0 }
        if let close = candidates.first(where: { $0.1.hasPrefix(target) || target.hasPrefix($0.1) }) { return close.0 }
        return nil
    }
}
