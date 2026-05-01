import Foundation

public enum SessionListNavigationDirection {
    case up
    case down
}

public enum SessionListKeyboardNavigator {
    public static func normalizedSelection(currentID: String?, ids: [String]) -> String? {
        guard !ids.isEmpty else { return nil }
        guard let currentID, ids.contains(currentID) else { return ids.first }
        return currentID
    }

    public static func nextSelection(
        currentID: String?,
        ids: [String],
        direction: SessionListNavigationDirection
    ) -> String? {
        guard !ids.isEmpty else { return nil }

        guard let currentID,
              let currentIndex = ids.firstIndex(of: currentID) else {
            return ids.first
        }

        switch direction {
        case .up:
            return ids[max(currentIndex - 1, 0)]
        case .down:
            return ids[min(currentIndex + 1, ids.count - 1)]
        }
    }
}
