import Foundation
import Observation
import SwiftUI

/// First-run assistant: check the Mac → prepare Windows → install Steam → sign in.
@Observable
@MainActor
final class SetupModel {
    enum Step: Int, CaseIterable, Identifiable {
        case mac, windows, steam, login
        var id: Int { rawValue }

        var title: LocalizedStringKey {
            switch self {
            case .mac: return "Checking your Mac"
            case .windows: return "Preparing the engine"
            case .steam: return "Installing Steam"
            case .login: return "Sign in"
            }
        }

        var symbol: String {
            switch self {
            case .mac: return "macbook"
            case .windows: return "gearshape.2"
            case .steam: return "arrow.down.app"
            case .login: return "person.crop.circle"
            }
        }
    }

    enum Phase: Equatable {
        case welcome
        case running(Step)
        case needsRosetta
        case waitingForLogin
        case failed(Step, String)
        case finished
    }

    weak var model: AppModel?
    var phase: Phase = .welcome
    var progress: Double? = nil
    var detail: String = ""
    var completed: Set<Step> = []
    /// Steps the user chose to skip (Steam and, with it, signing in).
    var skipped: Set<Step> = []
    private var skippingSteam = false

    var currentStep: Step? {
        switch phase {
        case .running(let s), .failed(let s, _): return s
        case .needsRosetta: return .mac
        case .waitingForLogin: return .login
        case .welcome: return nil
        case .finished: return nil
        }
    }

    private var task: Task<Void, Never>?

    func reset() {
        task?.cancel()
        phase = .welcome
        progress = nil
        detail = ""
        completed = []
        skipped = []
        skippingSteam = false
    }

    func start() {
        task?.cancel()
        task = Task { await run() }
    }

    func retry() { start() }

    private func set(_ step: Step, progress: Double?, _ detail: String) {
        if skippingSteam { return }
        withAnimation(.spring(duration: 0.5)) {
            phase = .running(step)
            self.progress = progress
            self.detail = detail
        }
    }

    private func complete(_ step: Step) {
        if skippingSteam { return }
        _ = withAnimation(.spring(duration: 0.6, bounce: 0.25)) { completed.insert(step) }
    }

    private func run() async {
        guard let model else { return }
        let steam = model.steam
        let paths = model.paths
        let language = model.language

        // 1. Mac
        set(.mac, progress: nil, String(localized: "Checking the chip, macOS and Rosetta 2…"))
        try? await Task.sleep(nanoseconds: 900_000_000)
        guard MacSystem.isAppleSilicon else {
            fail(.mac, String(localized: "Cider needs a Mac with Apple silicon (M1 or later).")); return
        }
        guard paths.runtimeIsPresent else {
            fail(.mac, SteamManager.SteamError.runtimeMissing.errorDescription!); return
        }
        if !MacSystem.isRosettaInstalled {
            withAnimation(.spring) { phase = .needsRosetta }
            return
        }
        complete(.mac)

        // 2. Windows
        if !paths.prefixExists {
            set(.windows, progress: 0, String(localized: "Getting everything ready for your games…"))
            let watcher = Task { [weak self] in
                // wineboot populates system32 + syswow64; count files for a real progress bar.
                while !Task.isCancelled {
                    let n = Self.fileCount(paths.system32) + Self.fileCount(paths.driveC.appendingPathComponent("windows/syswow64"))
                    await MainActor.run { self?.progress = min(0.97, Double(n) / Self.expectedPrefixFiles) }
                    try? await Task.sleep(nanoseconds: 400_000_000)
                }
            }
            do {
                try await steam.createPrefix(language: language)
            } catch {
                watcher.cancel()
                fail(.windows, error.localizedDescription); return
            }
            watcher.cancel()
        } else {
            set(.windows, progress: 1, String(localized: "The engine is already set up."))
            try? await steam.applyPrefixDefaults(language: language)
        }
        progress = 1
        complete(.windows)

        // 3. Steam
        do {
            if !steam.isInstalled {
                set(.steam, progress: 0, String(localized: "Downloading the official Steam installer…"))
                let installer = try await steam.downloadInstaller { p in
                    Task { @MainActor [weak self] in self?.progress = p * 0.15 }
                }
                set(.steam, progress: 0.15, String(localized: "Installing Steam…"))
                try await steam.runInstaller(installer)
            }
            if !steam.isBootstrapped || !steam.isWebhelperPatched {
                set(.steam, progress: 0.2, String(localized: "Steam is updating for the first time…"))
                try await steam.bootstrap(language: language, progress: { fraction, done, total in
                    Task { @MainActor [weak self] in
                        self?.progress = 0.2 + fraction * 0.78
                        if total > 0 {
                            let f = ByteCountFormatter()
                            f.countStyle = .file
                            self?.detail = String(localized: "Downloading Steam: \(f.string(fromByteCount: Int64(done) * 1024)) of \(f.string(fromByteCount: Int64(total) * 1024))")
                        }
                    }
                }, onStall: {
                    Task { @MainActor [weak self] in
                        self?.detail = String(localized: "Steam had stalled. I restarted it; it carries on by itself…")
                    }
                })
            } else {
                try await steam.installService()
            }
        } catch {
            fail(.steam, error.localizedDescription); return
        }
        progress = 1
        complete(.steam)

        // 4. Login
        await waitForLogin()
    }

    func waitForLogin() async {
        guard let model, !skippingSteam else { return }
        let steam = model.steam
        withAnimation(.spring) {
            phase = .waitingForLogin
            progress = nil
            detail = String(localized: "The Steam window will open. Sign in with your account and come back here.")
        }
        if !steam.isSteamRunning() {
            let session = model.session(for: nil)
            do {
                try await steam.start(session: session, language: model.language)
                model.state.lastSession = session
            } catch {
                fail(.login, error.localizedDescription); return
            }
        }
        // Signed in = Steam reports an active user.
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            if !steam.loginUsers().isEmpty, await steam.activeUserID() != 0 { break }
        }
        guard !Task.isCancelled else { return }
        complete(.login)
        model.steamUser = steam.currentUser
        withAnimation(.spring(duration: 0.7, bounce: 0.3)) { phase = .finished }
    }

    func installRosetta() {
        task?.cancel()
        task = Task {
            set(.mac, progress: nil, String(localized: "Installing Rosetta 2. This can take a couple of minutes…"))
            if await MacSystem.installRosetta() {
                await run()
            } else {
                withAnimation { phase = .needsRosetta }
                model?.showToast(String(localized: "Rosetta 2 couldn't be installed."), error: true)
            }
        }
    }

    func reopenSteamForLogin() {
        task?.cancel()
        task = Task {
            if let model, !model.steam.isSteamRunning() {
                await waitForLogin()
            } else {
                model?.openSteam()
                await waitForLogin()
            }
        }
    }

    /// "Ahora no": continue without Steam. It can be installed later from the Steam section.
    func skipSteam() {
        skippingSteam = true
        task?.cancel()
        let wine = model?.wine
        Task { await wine?.killAll() }
        withAnimation(.spring(duration: 0.6, bounce: 0.2)) {
            skipped = [.steam, .login]
            progress = nil
            phase = .finished
        }
    }

    func skipLogin() {
        task?.cancel()
        model?.finishOnboarding()
    }

    private func fail(_ step: Step, _ message: String) {
        if skippingSteam || Task.isCancelled { return }
        model?.wine.appendLog("Setup failed at \(step): \(message)")
        withAnimation(.spring) { phase = .failed(step, message) }
    }

    nonisolated static let expectedPrefixFiles: Double = 1900

    nonisolated static func fileCount(_ url: URL) -> Int {
        (try? FileManager.default.contentsOfDirectory(atPath: url.path).count) ?? 0
    }

    /// Static states for screenshots / design review (`-CiderOnboardingPreview <name>`).
    func preview(_ name: String) {
        switch name {
        case "welcome": phase = .welcome
        case "mac": phase = .running(.mac); detail = String(localized: "Checking the chip, macOS and Rosetta 2…")
        case "rosetta": phase = .needsRosetta
        case "windows":
            completed = [.mac]; phase = .running(.windows); progress = 0.62
            detail = String(localized: "Getting everything ready for your games…")
        case "steam":
            completed = [.mac, .windows]; phase = .running(.steam); progress = 0.48
            detail = String(localized: "Downloading Steam: 168 MB of 336 MB")
        case "login":
            completed = [.mac, .windows, .steam]; phase = .waitingForLogin
            detail = String(localized: "The Steam window will open. Sign in with your account and come back here.")
        case "done": completed = Set(Step.allCases); phase = .finished
        case "failed": completed = [.mac]; phase = .failed(.windows, "wineboot exited with code 1")
        default: break
        }
    }
}
