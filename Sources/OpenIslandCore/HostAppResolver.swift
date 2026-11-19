import Darwin
import Foundation

/// Names the macOS app hosting a process by walking its parent chain up to the
/// first ancestor whose executable lives inside an `.app` bundle.
public enum HostAppResolver {
    public static func hostAppName(startingAt pid: pid_t = getppid()) -> String? {
        var pid = pid
        for _ in 0..<20 where pid > 1 {
            if let path = executablePath(of: pid),
               let bundleURL = outermostAppBundle(containing: path) {
                return appName(for: bundleURL)
            }
            pid = parentPID(of: pid)
        }
        return nil
    }

    /// The outermost bundle wins so Electron/Chromium helpers resolve to their host app.
    static func outermostAppBundle(containing executablePath: String) -> URL? {
        guard let range = executablePath.range(of: ".app/") else { return nil }
        return URL(fileURLWithPath: String(executablePath[..<range.lowerBound]) + ".app")
    }

    static func appName(for bundleURL: URL) -> String {
        let info = NSDictionary(contentsOf: bundleURL.appendingPathComponent("Contents/Info.plist"))
        for key in ["CFBundleDisplayName", "CFBundleName"] {
            if let name = (info?[key] as? String)?.trimmingCharacters(in: .whitespaces), !name.isEmpty {
                return name
            }
        }
        return bundleURL.deletingPathExtension().lastPathComponent
    }

    private static func executablePath(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return nil }
        return String(cString: buffer)
    }

    private static func parentPID(of pid: pid_t) -> pid_t {
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return 0 }
        return info.kp_eproc.e_ppid
    }
}
