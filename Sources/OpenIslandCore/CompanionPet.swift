import Foundation

public enum CompanionPet: String, CaseIterable, Codable, Sendable {
    case cat
    case ghost
    case robot

    /// Picks a deterministic pet for the calendar day containing `date`.
    public static func dailyPick(at date: Date = Date()) -> CompanionPet {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let dayNumber = Int(startOfDay.timeIntervalSince1970 / 86_400)
        let index = abs(dayNumber) % CompanionPet.allCases.count
        return CompanionPet.allCases[index]
    }

    public var displayName: String {
        switch self {
        case .cat:   "Cat"
        case .ghost: "Ghost"
        case .robot: "Robot"
        }
    }
}

/// A single frame of a pixel pet: 2D grid of bool (true = filled, false = transparent).
public typealias PixelPetGrid = [[Bool]]

public enum PixelPetSprite {
    /// Parses an ASCII pixel grid where '.' is transparent and any other
    /// non-whitespace character is filled. Skips blank lines.
    public static func parseGrid(_ ascii: String) -> PixelPetGrid {
        ascii
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map { line in
                line.map { ch in
                    ch != "." && !ch.isWhitespace
                }
            }
    }
}
