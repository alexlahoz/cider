import AppKit
import Foundation
import Observation

/// In-app updates from GitHub Releases: check, download the DMG, swap the app bundle, relaunch.
@Observable
@MainActor
final class Updater {
    struct Release: Equatable, Sendable {
        var version: String
        var notes: String
        var dmgURL: URL
        var size: Int64
        var pageURL: URL?
    }

    enum State: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case downloading(Release, Double)
        case installing(Release)
        case failed(String)
    }

    var state: State = .idle
    var showSheet = false

    /// `owner/repo` on GitHub, from Info.plist (CiderUpdateRepository).
    let repository = Bundle.main.object(forInfoDictionaryKey: "CiderUpdateRepository") as? String

    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    var availableRelease: Release? {
        switch state {
        case .available(let r), .downloading(let r, _), .installing(let r): return r
        default: return nil
        }
    }

    private static let lastCheckKey = "CiderLastUpdateCheck"

    /// Automatic check, every time Cider opens.
    func checkOnLaunch() {
        Task { await check(userInitiated: false) }
    }

    func check(userInitiated: Bool) async {
        if case .downloading = state { return }
        if case .installing = state { return }
        state = .checking
        UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
        do {
            let release = try await fetchLatest()
            if Self.compare(release.version, currentVersion) == .orderedDescending {
                state = .available(release)
                if userInitiated { showSheet = true }
            } else {
                state = .upToDate
            }
        } catch {
            state = userInitiated ? .failed(Self.describe(error)) : .idle
        }
    }

    // MARK: feed

    private func feedURL() -> URL? {
        if let override = ProcessInfo.processInfo.environment["CIDER_UPDATE_FEED"] { return URL(string: override) }
        guard let repository, !repository.isEmpty else { return nil }
        return URL(string: "https://api.github.com/repos/\(repository)/releases/latest")
    }

    private func fetchLatest() async throws -> Release {
        guard let url = feedURL() else { throw UpdateError.notConfigured }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 20
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 404 { throw UpdateError.noReleases }
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String,
              let assets = json["assets"] as? [[String: Any]],
              let dmg = assets.first(where: { ($0["name"] as? String)?.lowercased().hasSuffix(".dmg") == true }),
              let link = (dmg["browser_download_url"] as? String).flatMap(URL.init(string:))
        else { throw UpdateError.badFeed }
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
        return Release(version: version,
                       notes: json["body"] as? String ?? "",
                       dmgURL: link,
                       size: (dmg["size"] as? NSNumber)?.int64Value ?? 0,
                       pageURL: (json["html_url"] as? String).flatMap(URL.init(string:)))
    }

    /// Semantic-ish version comparison ("1.10.0" > "1.9.2").
    nonisolated static func compare(_ a: String, _ b: String) -> ComparisonResult {
        let pa = a.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        let pb = b.split(separator: ".").map { Int($0.prefix(while: \.isNumber)) ?? 0 }
        for i in 0..<max(pa.count, pb.count) {
            let x = i < pa.count ? pa[i] : 0, y = i < pb.count ? pb[i] : 0
            if x != y { return x < y ? .orderedAscending : .orderedDescending }
        }
        return .orderedSame
    }

    // MARK: install

    /// Where the running app lives, if Cider may replace it in place.
    private var replaceableAppURL: URL? {
        let app = Bundle.main.bundleURL
        guard app.pathExtension == "app",
              !app.path.contains("/AppTranslocation/"),
              FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path)
        else { return nil }
        return app
    }

    func install(_ release: Release, before: @escaping () async -> Void) {
        Task { await performInstall(release, before: before) }
    }

    private func performInstall(_ release: Release, before: () async -> Void) async {
        state = .downloading(release, 0)
        let workDir = CiderPaths.shared.data.appendingPathComponent("updates", isDirectory: true)
        try? FileManager.default.removeItem(at: workDir)
        try? FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        let dmg = workDir.appendingPathComponent("Cider-\(release.version).dmg")
        do {
            // 1. Download
            let delegate = DownloadProgressDelegate { [weak self] p in
                Task { @MainActor in self?.state = .downloading(release, p) }
            }
            let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            defer { session.finishTasksAndInvalidate() }
            let (tmp, response) = try await session.download(from: release.dmgURL)
            if let http = response as? HTTPURLResponse, http.statusCode != 200 { throw UpdateError.download }
            try FileManager.default.moveItem(at: tmp, to: dmg)

            guard let target = replaceableAppURL else {
                // Not installed somewhere writable: let the user drag it.
                NSWorkspace.shared.open(dmg)
                state = .available(release)
                showSheet = false
                return
            }

            // 2. Unpack next to the current app (same volume, so the final swap is a rename).
            state = .installing(release)
            let mount = workDir.appendingPathComponent("mount", isDirectory: true)
            try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
            guard await Self.run("/usr/bin/hdiutil", ["attach", dmg.path, "-nobrowse", "-readonly", "-noverify",
                                                      "-mountpoint", mount.path]) == 0 else { throw UpdateError.mount }
            let staged = target.deletingLastPathComponent().appendingPathComponent(".Cider-\(release.version)-update.app")
            try? FileManager.default.removeItem(at: staged)
            let copied = await Self.run("/usr/bin/ditto", [mount.appendingPathComponent("Cider.app").path, staged.path])
            _ = await Self.run("/usr/bin/hdiutil", ["detach", mount.path, "-force"])
            guard copied == 0 else { throw UpdateError.copy }

            // 3. Sanity checks on the new bundle.
            let newVersion = Bundle(url: staged)?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            guard newVersion == release.version,
                  await Self.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", staged.path]) == 0
            else {
                try? FileManager.default.removeItem(at: staged)
                throw UpdateError.verify
            }

            // 4. Close games / Steam, then swap the bundle after Cider quits and relaunch it.
            await before()
            let script = """
            #!/bin/sh
            while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
            OLD="\(target.path)"; NEW="\(staged.path)"
            rm -rf "$OLD.previous"
            mv "$OLD" "$OLD.previous" && mv "$NEW" "$OLD" && rm -rf "$OLD.previous"
            [ -d "$OLD" ] || mv "$OLD.previous" "$OLD"
            /usr/bin/xattr -dr com.apple.quarantine "$OLD" 2>/dev/null
            /usr/bin/open "$OLD"
            rm -rf "\(workDir.path)"
            """
            let scriptURL = FileManager.default.temporaryDirectory.appendingPathComponent("cider-update.sh")
            try script.write(to: scriptURL, atomically: true, encoding: .utf8)
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/sh")
            p.arguments = [scriptURL.path]
            try p.run()
            // A sheet blocks -terminate:, so close it first; force the exit if AppKit still refuses
            // (everything Cider needs is already saved on disk).
            showSheet = false
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { NSApp.terminate(nil) }
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) { exit(0) }
        } catch {
            state = .failed(Self.describe(error))
        }
    }

    private static func run(_ tool: String, _ args: [String]) async -> Int32 {
        await withCheckedContinuation { cont in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: tool)
            p.arguments = args
            p.standardOutput = FileHandle.nullDevice
            p.standardError = FileHandle.nullDevice
            p.terminationHandler = { cont.resume(returning: $0.terminationStatus) }
            do { try p.run() } catch { cont.resume(returning: -1) }
        }
    }

    enum UpdateError: Error {
        case notConfigured, noReleases, badFeed, download, mount, copy, verify
    }

    private static func describe(_ error: Error) -> String {
        switch error as? UpdateError {
        case .notConfigured: return String(localized: "Updates aren't configured in this build.")
        case .noReleases: return String(localized: "There are no published versions yet.")
        case .badFeed: return String(localized: "The update information couldn't be read.")
        case .download: return String(localized: "The update couldn't be downloaded.")
        case .mount, .copy: return String(localized: "The update couldn't be unpacked.")
        case .verify: return String(localized: "The downloaded update is damaged. Try again.")
        case nil: return error.localizedDescription
        }
    }
}
