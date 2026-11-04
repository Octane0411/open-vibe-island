import Foundation

/// Resolves which VS Code family editor hosted a shell.
///
/// Every fork of VS Code inherits `TERM_PROGRAM=vscode` from upstream, so that
/// variable alone identifies the family but not the member. Cursor, Windsurf,
/// Trae, and Qoder all land on the same value, and only some builds export a
/// fork-specific marker such as `CURSOR_TRACE_ID`. Tagging those sessions as
/// "VS Code" sends the jump to `com.microsoft.VSCode`, which then fails
/// outright on machines where upstream VS Code is not installed.
///
/// Callers should consult this only once `TERM_PROGRAM` has already placed the
/// host in the VS Code family. The corroborating signals below (`__CFBundleIdentifier`,
/// the bundled git askpass paths) are injected by the hosting GUI app and can
/// leak across apps through macOS environment inheritance, so they are safe for
/// picking a family member but not for identifying the family itself.
public enum VSCodeFamilyHost {
    /// Bundle identifiers of VS Code family editors, lowercased for matching.
    private static let displayNamesByBundleIdentifier: [String: String] = [
        "com.todesktop.230313mzl4w4u92": "Cursor",
        "com.exafunction.windsurf": "Windsurf",
        "com.trae.app": "Trae",
        "cn.trae.app": "Trae",
        "com.qoder.qoder": "Qoder",
        "com.microsoft.vscodeinsiders": "VS Code Insiders",
        "com.microsoft.vscode": "VS Code",
    ]

    /// Application bundle path fragments, checked against env vars that carry
    /// an absolute path into the hosting app bundle.
    private static let displayNamesByBundlePathFragment: [(fragment: String, displayName: String)] = [
        ("/cursor.app/", "Cursor"),
        ("/windsurf.app/", "Windsurf"),
        ("/trae.app/", "Trae"),
        ("/qoder.app/", "Qoder"),
        ("/visual studio code - insiders.app/", "VS Code Insiders"),
        ("/visual studio code.app/", "VS Code"),
    ]

    /// Env vars whose values point into the hosting editor's app bundle. VS
    /// Code and every fork export these for the bundled git extension.
    private static let bundlePathEnvironmentKeys = [
        "VSCODE_GIT_ASKPASS_NODE",
        "VSCODE_GIT_ASKPASS_MAIN",
        "GIT_ASKPASS",
    ]

    /// Returns the display name of the VS Code family editor hosting the shell,
    /// falling back to `defaultDisplayName` when no fork can be identified.
    public static func displayName(
        from environment: [String: String],
        default defaultDisplayName: String = "VS Code"
    ) -> String {
        // Cursor's own marker, when the build exports it.
        if environment["CURSOR_TRACE_ID"] != nil {
            return "Cursor"
        }

        if let bundleIdentifier = environment["__CFBundleIdentifier"]?.lowercased(),
           let displayName = displayNamesByBundleIdentifier[bundleIdentifier] {
            return displayName
        }

        for key in bundlePathEnvironmentKeys {
            guard let value = environment[key]?.lowercased(), !value.isEmpty else {
                continue
            }

            if let match = displayNamesByBundlePathFragment.first(where: { value.contains($0.fragment) }) {
                return match.displayName
            }
        }

        return defaultDisplayName
    }
}
