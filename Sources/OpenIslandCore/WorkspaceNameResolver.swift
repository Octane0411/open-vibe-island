import Foundation

public enum WorkspaceNameResolver {
    private static let worktreeMarkers = ["/.claude/worktrees/", "/.git/worktrees/"]

    public static func workspaceName(for cwd: String) -> String {
        // Decode `\xHH` path dumps (non-ASCII cwd) before taking the last
        // path component so titles show readable text, not byte escapes.
        let normalizedCWD = HexEscapedUTF8.decodeIfNeeded(cwd)
        let url = URL(fileURLWithPath: normalizedCWD)
        let path = url.standardizedFileURL.path

        for marker in worktreeMarkers {
            if let range = path.range(of: marker) {
                let projectPath = String(path[path.startIndex..<range.lowerBound])
                let projectName = HexEscapedUTF8.decodeIfNeeded(
                    URL(fileURLWithPath: projectPath).lastPathComponent
                )
                if !projectName.isEmpty {
                    return projectName
                }
            }
        }

        let name = HexEscapedUTF8.decodeIfNeeded(url.lastPathComponent)
        return name.isEmpty ? "Workspace" : name
    }

    public static func worktreeBranch(for cwd: String) -> String? {
        let path = URL(fileURLWithPath: cwd).standardizedFileURL.path

        for marker in worktreeMarkers {
            guard let range = path.range(of: marker) else {
                continue
            }

            let afterMarker = String(path[range.upperBound...])
            let branchName = afterMarker
                .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                .replacingOccurrences(of: "+", with: "/")

            return branchName.isEmpty ? nil : branchName
        }

        return nil
    }

    /// Absolute path of the nearest ancestor of `cwd` that contains a `.git`
    /// directory (or gitfile). Agents frequently run in deep subdirectories
    /// of a project (build dirs, run dirs); the project root — not the raw
    /// cwd — is what identifies the workspace window and folder.
    public static func projectRootPath(for cwd: String) -> String? {
        projectRootCache.value(for: cwd, compute: uncachedProjectRootPath(for:))
    }

    private static let projectRootCache = TimedCache<String, String?>(ttl: 30)

    private static func uncachedProjectRootPath(for cwd: String) -> String? {
        // Walk with plain string paths: URL.deletingLastPathComponent on "/"
        // yields "/..", then "/../..", forever — the URL walk never terminates
        // for cwd values outside any git repository.
        let fileManager = FileManager.default
        var path = URL(fileURLWithPath: cwd).standardizedFileURL.path

        while !path.isEmpty {
            if fileManager.fileExists(atPath: path + "/.git") {
                return path
            }

            let parent = (path as NSString).deletingLastPathComponent
            if parent == path || parent.isEmpty {
                return nil
            }
            path = parent
        }

        return nil
    }

    public static func gitBranch(for cwd: String) -> String? {
        // SwiftUI computed properties (e.g. `IslandSessionRow.summaryHeadlineText`)
        // call this on every layout pass. The walk-up-to-`.git` plus HEAD
        // read is dozens of `fileExists` calls; in a layout loop that
        // pegs CPU at 99 % until the layout settles. Cache results per
        // cwd with a short TTL so repeated layout passes hit memory.
        // 30 s is comfortably under any human-noticeable branch-switch
        // latency while collapsing burst calls into one IO.
        gitBranchCache.value(for: cwd, compute: uncachedGitBranch(for:))
    }

    private static let gitBranchCache = TimedCache<String, String?>(ttl: 30)

    private static func uncachedGitBranch(for cwd: String) -> String? {
        if let worktreeBranch = worktreeBranch(for: cwd) {
            return worktreeBranch
        }

        let fileManager = FileManager.default
        var directory = URL(fileURLWithPath: cwd).standardizedFileURL

        while true {
            let gitURL = directory.appendingPathComponent(".git")
            var isDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: gitURL.path, isDirectory: &isDirectory) {
                let gitDirectory: URL?
                if isDirectory.boolValue {
                    gitDirectory = gitURL
                } else {
                    gitDirectory = resolvedGitDirectory(fromGitFile: gitURL, relativeTo: directory)
                }

                if let gitDirectory {
                    return branchName(fromHeadFile: gitDirectory.appendingPathComponent("HEAD"))
                }
            }

            // Deleting the last component of a root "/" URL yields "/..",
            // then "/../..", endlessly — terminate on the string path instead
            // so cwd values outside any git repository cannot spin forever.
            let parentPath = (directory.path as NSString).deletingLastPathComponent
            if parentPath == directory.path || parentPath.isEmpty {
                return nil
            }
            directory = URL(fileURLWithPath: parentPath)
        }
    }

    /// Test-only hook to drop cached branch lookups between assertions.
    static func resetGitBranchCacheForTests() {
        gitBranchCache.removeAll()
    }

    private static func resolvedGitDirectory(fromGitFile gitFile: URL, relativeTo directory: URL) -> URL? {
        guard let content = try? String(contentsOf: gitFile, encoding: .utf8) else {
            return nil
        }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let prefix = "gitdir:"
        guard trimmed.lowercased().hasPrefix(prefix) else {
            return nil
        }

        let rawPath = trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespaces)
        guard !rawPath.isEmpty else {
            return nil
        }

        if rawPath.hasPrefix("/") {
            return URL(fileURLWithPath: rawPath).standardizedFileURL
        }

        return directory.appendingPathComponent(rawPath).standardizedFileURL
    }

    private static func branchName(fromHeadFile headURL: URL) -> String? {
        guard let content = try? String(contentsOf: headURL, encoding: .utf8) else {
            return nil
        }

        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
        let refPrefix = "ref: refs/heads/"
        guard trimmed.hasPrefix(refPrefix) else {
            return nil
        }

        let branch = trimmed.dropFirst(refPrefix.count)
        return branch.isEmpty ? nil : String(branch)
    }
}
