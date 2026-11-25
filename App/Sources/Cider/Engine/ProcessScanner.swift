import Darwin
import Foundation

/// Finds the Windows processes running inside Cider's prefix.
///
/// Wine rewrites each process's argv with its Windows path (e.g. `C:\...\steam.exe`), so `ps`
/// shows us what is running. Other Wine installs on the same Mac (another prefix) are told apart
/// by the process's working directory, which Wine keeps inside the prefix.
enum ProcessScanner {
    struct WinProcess: Sendable, Hashable {
        let pid: Int32
        let command: String
        var cwd: String? = nil
        var lowercased: String { command.lowercased() }
    }

    static func cwd(of pid: Int32) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        let r = proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size)
        guard r == size else { return nil }
        return withUnsafePointer(to: &info.pvi_cdir.vip_path) {
            $0.withMemoryRebound(to: CChar.self, capacity: Int(MAXPATHLEN)) { String(cString: $0) }
        }
    }

    /// Real path (keeps "/private" in /private/tmp, unlike `resolvingSymlinksInPath()`).
    static func canonicalPath(_ path: String) -> String {
        guard let p = realpath(path, nil) else { return path }
        defer { free(p) }
        return String(cString: p)
    }

    /// All Wine processes (Windows executables) whose working directory is inside `root`
    /// (Cider's data folder, which contains the prefix).
    static func processes(under rootURL: URL) -> [WinProcess] {
        let root = canonicalPath(rootURL.path)
        return allWindowsProcesses().filter { $0.cwd?.hasPrefix(root) == true }
    }

    /// Every Windows process on the Mac (any prefix), with its working directory.
    static func allWindowsProcesses() -> [WinProcess] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/ps")
        p.arguments = ["-axww", "-o", "pid=,command="]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do { try p.run() } catch { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        var result: [WinProcess] = []
        for line in String(decoding: data, as: UTF8.self).split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard let space = trimmed.firstIndex(of: " "), let pid = Int32(trimmed[..<space]) else { continue }
            let cmd = String(trimmed[space...]).trimmingCharacters(in: .whitespaces)
            // Windows processes show up as "X:\\...\\app.exe", or with the Unix path they were
            // started with ("/…/app.exe"). Skip wineserver, the preloader and other helpers.
            let isWindowsPath = cmd.count > 3 && cmd.dropFirst().hasPrefix(":\\")
            let isUnixExe = cmd.hasPrefix("/") && cmd.lowercased().contains(".exe")
            guard isWindowsPath || isUnixExe else { continue }
            result.append(WinProcess(pid: pid, command: cmd, cwd: cwd(of: pid)))
        }
        return result
    }
}
