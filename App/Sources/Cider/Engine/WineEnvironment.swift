import Foundation

/// Runs Wine commands against Cider's private prefix.
///
/// Processes are spawned directly with `Process` (never through `nohup`, `env` or other
/// SIP-protected binaries, which would strip the `DYLD_*` variables Wine relies on).
final class WineEnvironment: @unchecked Sendable {
    let paths: CiderPaths

    init(paths: CiderPaths = .shared) {
        self.paths = paths
    }

    struct Options: Sendable {
        var msync = true
        var fpsHUD = false
        var resizableWindows = true
        /// Windows sees the screen this many times smaller; macOS scales windows up (patched winemac).
        var renderScale: Double?
        var extra: [String: String] = [:]
    }

    func environment(_ options: Options = Options()) -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        // Keep the inherited environment small and predictable.
        for key in env.keys where key.hasPrefix("WINE") || key.hasPrefix("DXMT") || key.hasPrefix("MTL_") || key.hasPrefix("CIDER_RESIZABLE") || key.hasPrefix("CIDER_RENDER") {
            env.removeValue(forKey: key)
        }
        env["WINEPREFIX"] = paths.prefix.path
        env["WINEDEBUG"] = "-all"
        env["WINEMSYNC"] = options.msync ? "1" : "0"
        env["DXMT_LOG_PATH"] = paths.logs.path
        env["MTL_HUD_ENABLED"] = options.fpsHUD ? "1" : "0"
        env["CIDER_RESIZABLE_WINDOWS"] = options.resizableWindows ? "1" : "0"
        if let scale = options.renderScale, scale > 1 {
            env["CIDER_RENDER_SCALE"] = String(scale)
        }
        env["PATH"] = paths.wineRoot.appendingPathComponent("bin").path + ":/usr/bin:/bin:/usr/sbin:/sbin"
        for (k, v) in options.extra { env[k] = v }
        return env
    }

    /// The shared log, opened in append mode so Wine processes and Cider never overwrite each other.
    private func logHandle() -> FileHandle? {
        paths.ensureDirectories()
        let fd = open(paths.wineLog.path, O_WRONLY | O_APPEND | O_CREAT, 0o644)
        guard fd >= 0 else { return nil }
        return FileHandle(fileDescriptor: fd, closeOnDealloc: true)
    }

    func appendLog(_ line: String) {
        guard let h = logHandle() else { return }
        let stamp = ISO8601DateFormatter().string(from: Date())
        h.write("[cider \(stamp)] \(line)\n".data(using: .utf8)!)
        try? h.close()
    }

    /// Starts `wine <args>` and returns the running process. Output goes to the Wine log.
    @discardableResult
    func spawn(_ args: [String], options: Options = Options(), cwd: URL? = nil,
               onExit: (@Sendable (Int32) -> Void)? = nil) throws -> Process {
        try launch(executable: paths.wine, args: args, options: options, cwd: cwd, onExit: onExit)
    }

    @discardableResult
    func launch(executable: URL, args: [String], options: Options = Options(), cwd: URL? = nil,
                onExit: (@Sendable (Int32) -> Void)? = nil) throws -> Process {
        let p = Process()
        p.executableURL = executable
        p.arguments = args
        p.environment = environment(options)
        p.currentDirectoryURL = cwd ?? paths.data
        let log = logHandle()
        p.standardOutput = log ?? FileHandle.nullDevice
        p.standardError = log ?? FileHandle.nullDevice
        p.standardInput = FileHandle.nullDevice
        if let onExit {
            p.terminationHandler = { proc in onExit(proc.terminationStatus) }
        }
        appendLog("$ \(executable.lastPathComponent) \(args.joined(separator: " "))")
        try p.run()
        try? log?.close()
        return p
    }

    /// Runs `wine <args>` and waits for it to finish.
    @discardableResult
    func run(_ args: [String], options: Options = Options(), timeout: TimeInterval? = nil) async throws -> Int32 {
        try await runExecutable(paths.wine, args: args, options: options, timeout: timeout)
    }

    @discardableResult
    func runExecutable(_ exe: URL, args: [String], options: Options = Options(), timeout: TimeInterval? = nil) async throws -> Int32 {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Int32, Error>) in
            do {
                let once = OnceFlag()
                let p = try launch(executable: exe, args: args, options: options) { status in
                    if once.take() { cont.resume(returning: status) }
                }
                if let timeout {
                    DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                        if p.isRunning { p.terminate() }
                    }
                }
            } catch {
                cont.resume(throwing: error)
            }
        }
    }

    /// Captures stdout of `wine <args>` (used for `reg query`).
    func capture(_ args: [String], timeout: TimeInterval = 20) async -> String {
        await withCheckedContinuation { (cont: CheckedContinuation<String, Never>) in
            let p = Process()
            p.executableURL = paths.wine
            p.arguments = args
            p.environment = environment()
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice
            let once = OnceFlag()
            p.terminationHandler = { _ in
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if once.take() { cont.resume(returning: String(decoding: data, as: UTF8.self)) }
            }
            do { try p.run() } catch {
                if once.take() { cont.resume(returning: "") }
                return
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) {
                if p.isRunning { p.terminate() }
            }
        }
    }

    // MARK: wineserver

    func killAll() async {
        _ = try? await runExecutable(paths.wineserver, args: ["-k"], timeout: 20)
    }

    func waitForServer(timeout: TimeInterval = 300) async {
        _ = try? await runExecutable(paths.wineserver, args: ["-w"], timeout: timeout)
    }

    // MARK: registry

    /// Imports registry content (REGEDIT4 syntax, without the header) in one go.
    func importRegistry(_ body: String) async throws {
        let file = paths.data.appendingPathComponent("cider-import.reg")
        let text = "REGEDIT4\r\n\r\n" + body.replacingOccurrences(of: "\n", with: "\r\n") + "\r\n"
        try text.data(using: .utf8)!.write(to: file)
        try await run(["regedit", "/S", Self.windowsPath(file)], timeout: 60)
        try? FileManager.default.removeItem(at: file)
    }

    /// Unix path as seen from Windows through the Z: drive.
    static func windowsPath(_ url: URL) -> String {
        "Z:" + url.path.replacingOccurrences(of: "/", with: "\\")
    }

    static func regEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}

/// Thread-safe one-shot flag used to resume continuations exactly once.
final class OnceFlag: @unchecked Sendable {
    private var done = false
    private let lock = NSLock()
    func take() -> Bool {
        lock.lock(); defer { lock.unlock() }
        if done { return false }
        done = true
        return true
    }
}
