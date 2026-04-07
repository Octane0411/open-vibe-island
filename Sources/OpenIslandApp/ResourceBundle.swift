import Foundation

/// App-level resource bundle accessor that searches both Contents/Resources/
/// (signed .app bundles) and the .app root (SPM default / dev builds).
///
/// SPM's auto-generated `Bundle.module` only searches the .app root, which
/// breaks code signing (macOS rejects "unsealed contents" at the bundle root).
/// Use `Bundle.appResources` instead of `Bundle.module` throughout the app.
enum ResourceBundle {
    static let bundle: Bundle = {
        let bundleName = "OpenIsland_OpenIslandApp"

        let candidates = [
            // Signed .app: Contents/Resources/
            Bundle.main.resourceURL,
            // SPM default / dev builds: .app root
            Bundle.main.bundleURL,
        ]

        for candidate in candidates {
            if let url = candidate?.appendingPathComponent(bundleName + ".bundle"),
               let bundle = Bundle(url: url)
            {
                return bundle
            }
        }

        // Last resort: SPM's generated accessor (works in dev via hardcoded .build/ path)
        return .module
    }()
}

extension Bundle {
    /// Use this instead of `Bundle.module` for resource lookups.
    static var appResources: Bundle { ResourceBundle.bundle }
}
