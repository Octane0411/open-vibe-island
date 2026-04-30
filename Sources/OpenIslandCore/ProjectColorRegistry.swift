import Foundation

public struct ProjectColor: Equatable, Codable, Sendable {
    public var red: Double
    public var green: Double
    public var blue: Double
    public init(red: Double, green: Double, blue: Double) {
        self.red = red; self.green = green; self.blue = blue
    }
}

public final class ProjectColorRegistry: @unchecked Sendable {
    private let storeURL: URL
    private var overrides: [String: ProjectColor] = [:]
    private let queue = DispatchQueue(label: "open-island.project-colors")

    public init(storeURL: URL) {
        self.storeURL = storeURL
        self.overrides = Self.load(from: storeURL)
    }

    public func color(for key: String) -> ProjectColor {
        queue.sync {
            if let override = overrides[key] { return override }
            let hashed = Self.hashColor(for: key)
            overrides[key] = hashed
            persist()
            return hashed
        }
    }

    public func setColor(_ color: ProjectColor, for key: String) {
        queue.sync {
            overrides[key] = color
            persist()
        }
    }

    public func resetAll() {
        queue.sync {
            overrides.removeAll()
            persist()
        }
    }

    public func pruneUnusedKeys(activePaths: Set<String>) {
        queue.sync {
            overrides = overrides.filter { activePaths.contains($0.key) }
            persist()
        }
    }

    public func knownKeys() -> [String] {
        queue.sync { Array(overrides.keys) }
    }

    // MARK: - Private

    private func persist() {
        do {
            try FileManager.default.createDirectory(
                at: storeURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let data = try JSONEncoder().encode(overrides)
            try data.write(to: storeURL, options: .atomic)
        } catch {
            // Persisting is best-effort — corruption recovery handles re-init next launch.
        }
    }

    private static func load(from url: URL) -> [String: ProjectColor] {
        guard FileManager.default.fileExists(atPath: url.path) else { return [:] }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([String: ProjectColor].self, from: data)
        } catch {
            return [:]
        }
    }

    /// FNV-1a 64-bit hash → HSL hue (fixed S=0.55, L=0.6) → RGB.
    static func hashColor(for key: String) -> ProjectColor {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in key.utf8 {
            hash ^= UInt64(byte)
            hash &*= 0x100000001b3
        }
        let hue = Double(hash % 360) / 360.0
        return hslToRGB(h: hue, s: 0.55, l: 0.6)
    }

    private static func hslToRGB(h: Double, s: Double, l: Double) -> ProjectColor {
        let c = (1 - abs(2 * l - 1)) * s
        let hp = h * 6
        let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
        let (r1, g1, b1): (Double, Double, Double)
        switch hp {
        case 0..<1: (r1, g1, b1) = (c, x, 0)
        case 1..<2: (r1, g1, b1) = (x, c, 0)
        case 2..<3: (r1, g1, b1) = (0, c, x)
        case 3..<4: (r1, g1, b1) = (0, x, c)
        case 4..<5: (r1, g1, b1) = (x, 0, c)
        default:    (r1, g1, b1) = (c, 0, x)
        }
        let m = l - c / 2
        return ProjectColor(red: r1 + m, green: g1 + m, blue: b1 + m)
    }
}
