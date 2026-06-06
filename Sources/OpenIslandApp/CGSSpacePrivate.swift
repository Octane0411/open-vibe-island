import CoreGraphics
import Foundation

// Private CoreGraphics Spaces APIs (SPI). Stable across recent macOS releases;
// used by space utilities such as WhichSpace, Spaceman, and alt-tab-macos.

typealias CGSConnectionID = UInt32

@_silgen_name("CGSMainConnectionID")
func CGSMainConnectionID() -> CGSConnectionID

@_silgen_name("CGSCopyManagedDisplaySpaces")
func CGSCopyManagedDisplaySpaces(_ connection: CGSConnectionID) -> CFArray

enum ManagedSpaceType: Int {
    case user = 0
    case fullscreenLegacy = 1
    case system = 2
    case fullscreen = 4
    case tiled = 5

    var isFullscreen: Bool {
        switch self {
        case .fullscreen, .fullscreenLegacy:
            return true
        case .user, .system, .tiled:
            return false
        }
    }
}

enum CGSSpaceQuery {
    static func currentSpaceType(on displayUUID: String?) -> ManagedSpaceType? {
        let connection = CGSMainConnectionID()
        guard let displays = CGSCopyManagedDisplaySpaces(connection) as? [[String: Any]] else {
            return nil
        }

        if let displayUUID,
           let display = displays.first(where: { ($0["Display Identifier"] as? String) == displayUUID }),
           let current = display["Current Space"] as? [String: Any],
           let rawType = current["type"] as? Int,
           let type = ManagedSpaceType(rawValue: rawType) {
            return type
        }

        // Single-display fallback when UUID matching fails.
        if displays.count == 1,
           let current = displays[0]["Current Space"] as? [String: Any],
           let rawType = current["type"] as? Int,
           let type = ManagedSpaceType(rawValue: rawType) {
            return type
        }

        return nil
    }
}
