import Foundation
import Metal

/// Facts about this Mac that Cider depends on.
enum MacSystem {
    static var isAppleSilicon: Bool {
        var info = utsname()
        uname(&info)
        let machine = withUnsafePointer(to: &info.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 256) { String(cString: $0) }
        }
        // A translated (Rosetta) process still reports x86_64 here, so also ask sysctl.
        var translated: Int32 = 0
        var size = MemoryLayout<Int32>.size
        sysctlbyname("sysctl.proc_translated", &translated, &size, nil, 0)
        return machine.hasPrefix("arm64") || translated == 1
    }

    static var isRosettaInstalled: Bool {
        FileManager.default.fileExists(atPath: "/Library/Apple/usr/libexec/oah/libRosettaRuntime")
    }

    static var osVersionString: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "macOS \(v.majorVersion).\(v.minorVersion)" + (v.patchVersion > 0 ? ".\(v.patchVersion)" : "")
    }

    static var gpuName: String { MTLCreateSystemDefaultDevice()?.name ?? "—" }

    static var chipName: String {
        var size = 0
        sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0)
        var buf = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("machdep.cpu.brand_string", &buf, &size, nil, 0)
        let s = String(cString: buf)
        return s.isEmpty ? "Apple Silicon" : s
    }

    static var memoryGB: Int { Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824) }

    /// Installs Rosetta 2, asking for an administrator password through the standard macOS dialog.
    static func installRosetta() async -> Bool {
        await withCheckedContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let prompt = String(localized: "Cider needs to install Apple's Rosetta 2 to run PC games.")
                let source = """
                do shell script "/usr/sbin/softwareupdate --install-rosetta --agree-to-license" with prompt "\(prompt)" with administrator privileges
                """
                var error: NSDictionary?
                NSAppleScript(source: source)?.executeAndReturnError(&error)
                cont.resume(returning: error == nil && isRosettaInstalled)
            }
        }
    }
}
