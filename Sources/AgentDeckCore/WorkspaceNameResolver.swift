import Foundation

public enum WorkspaceNameResolver {
    private static let worktreeMarkers = ["/.claude/worktrees/", "/.git/worktrees/"]

    public static func workspaceName(for cwd: String) -> String {
        let url = URL(fileURLWithPath: cwd)
        let path = url.standardizedFileURL.path

        for marker in worktreeMarkers {
            if let range = path.range(of: marker) {
                let projectPath = String(path[path.startIndex..<range.lowerBound])
                let projectName = URL(fileURLWithPath: projectPath).lastPathComponent
                if !projectName.isEmpty {
                    return projectName
                }
            }
        }

        let name = url.lastPathComponent
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
}
