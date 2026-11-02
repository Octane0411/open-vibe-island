import AppKit
import Darwin
import Foundation

/// Finds which running copy of Claude Desktop hosts a Claude Code session.
///
/// Claude Desktop runs Claude Code as a TTY-less subprocess, so the session
/// can't be matched to a window — but its process tree can be matched to an
/// app instance. With more than one copy running under the same bundle ID,
/// this walks each Claude Code process up to the copy that spawned it,
/// preferring the process whose working directory is the session's.
enum ClaudeDesktopHostLocator {
    static let bundleIdentifier = "com.anthropic.claudefordesktop"

    struct ProcessSnapshot: Equatable {
        var pid: pid_t
        var parentPID: pid_t
        var executablePath: String
        var currentDirectory: String?
    }

    /// Bundle path of the hosting copy, or `nil` when Claude Desktop isn't
    /// running (the caller then falls back to launching by bundle ID).
    static func hostAppPath(workingDirectory: String?) -> String? {
        var instances: [pid_t: String] = [:]
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier) {
            if let path = app.bundleURL?.path {
                instances[app.processIdentifier] = path
            }
        }
        // One copy (or none): nothing to choose, skip the process scan.
        guard instances.count > 1 else { return instances.values.first }
        return hostAppPath(
            instances: instances,
            processes: liveProcesses(),
            workingDirectory: workingDirectory
        )
    }

    /// - Parameters:
    ///   - instances: running Claude Desktop copies, pid → bundle path.
    ///   - processes: every process on the machine.
    static func hostAppPath(
        instances: [pid_t: String],
        processes: [ProcessSnapshot],
        workingDirectory: String?
    ) -> String? {
        guard instances.count > 1 else { return instances.values.first }

        let parents = Dictionary(processes.map { ($0.pid, $0.parentPID) }, uniquingKeysWith: { first, _ in first })
        let wantedDirectory = workingDirectory.map(normalized)
        var hostedCount: [pid_t: Int] = [:]

        for process in processes where isClaudeCodeExecutable(process.executablePath) {
            guard let host = ancestor(of: process.pid, in: Set(instances.keys), parents: parents) else {
                continue
            }
            if let wantedDirectory,
               let cwd = process.currentDirectory,
               normalized(cwd) == wantedDirectory {
                return instances[host]
            }
            hostedCount[host, default: 0] += 1
        }

        // No exact match: the copy running the most Claude Code sessions.
        let busiest = hostedCount.max { lhs, rhs in
            lhs.value == rhs.value ? lhs.key > rhs.key : lhs.value < rhs.value
        }
        return busiest.flatMap { instances[$0.key] }
    }

    private static func isClaudeCodeExecutable(_ path: String) -> Bool {
        (path as NSString).lastPathComponent == "claude" && path.contains("/claude-code/")
    }

    private static func normalized(_ path: String) -> String {
        (path as NSString).standardizingPath
    }

    private static func ancestor(
        of pid: pid_t,
        in candidates: Set<pid_t>,
        parents: [pid_t: pid_t]
    ) -> pid_t? {
        var current = pid
        for _ in 0..<12 {
            guard let parent = parents[current], parent > 1 else { return nil }
            if candidates.contains(parent) { return parent }
            current = parent
        }
        return nil
    }

    // MARK: - Live process table

    private static func liveProcesses() -> [ProcessSnapshot] {
        allProcessIDs().compactMap { pid in
            guard let parentPID = parentPID(of: pid) else { return nil }
            let executable = executablePath(of: pid) ?? ""
            // cwd is only needed for Claude Code processes; skip the syscall otherwise.
            let cwd = isClaudeCodeExecutable(executable) ? currentDirectory(of: pid) : nil
            return ProcessSnapshot(pid: pid, parentPID: parentPID, executablePath: executable, currentDirectory: cwd)
        }
    }

    private static func allProcessIDs() -> [pid_t] {
        let estimated = proc_listallpids(nil, 0)
        guard estimated > 0 else { return [] }
        var pids = [pid_t](repeating: 0, count: Int(estimated) + 64)
        let count = pids.withUnsafeMutableBufferPointer { buffer in
            proc_listallpids(buffer.baseAddress, Int32(buffer.count * MemoryLayout<pid_t>.size))
        }
        guard count > 0 else { return [] }
        return Array(pids.prefix(Int(count))).filter { $0 > 0 }
    }

    private static func executablePath(of pid: pid_t) -> String? {
        var buffer = [CChar](repeating: 0, count: 4 * Int(MAXPATHLEN))
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        guard length > 0 else { return nil }
        return String(cString: buffer)
    }

    private static func parentPID(of pid: pid_t) -> pid_t? {
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size) == size else { return nil }
        return pid_t(info.pbi_ppid)
    }

    private static func currentDirectory(of pid: pid_t) -> String? {
        var info = proc_vnodepathinfo()
        let size = Int32(MemoryLayout<proc_vnodepathinfo>.size)
        guard proc_pidinfo(pid, PROC_PIDVNODEPATHINFO, 0, &info, size) == size else { return nil }
        let path = withUnsafeBytes(of: info.pvi_cdir.vip_path) { raw in
            String(decoding: raw.prefix { $0 != 0 }, as: UTF8.self)
        }
        return path.isEmpty ? nil : path
    }
}
