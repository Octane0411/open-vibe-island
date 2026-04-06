import Foundation

/// Checks GitHub releases for available app updates.
@MainActor
@Observable
final class UpdateChecker {
    static let releasesURL = URL(string: "https://github.com/Octane0411/open-vibe-island/releases")!
    private static let checkInterval: TimeInterval = 1 * 60 * 60 // 1 hour

    private static let apiEndpoint = "https://api.github.com/repos/Octane0411/open-vibe-island/releases/latest"

    enum State: Equatable {
        case idle
        case checking
        case updateAvailable(version: String)
        case upToDate
        case failed
    }

    private(set) var state: State = .idle

    var hasUpdate: Bool {
        if case .updateAvailable = state { return true }
        return false
    }

    var latestVersion: String? {
        if case .updateAvailable(let v) = state { return v }
        return nil
    }

    private var lastCheckDate: Date?

    func checkIfNeeded() {
        if let last = lastCheckDate,
           Date().timeIntervalSince(last) < Self.checkInterval {
            return
        }
        check()
    }

    func check() {
        guard state != .checking else { return }
        state = .checking

        Task {
            do {
                let remoteVersion = try await Self.fetchLatestVersion()
                let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
                let hasNewer = Self.isVersionNewer(remoteVersion, than: currentVersion)

                lastCheckDate = Date()
                state = hasNewer ? .updateAvailable(version: remoteVersion) : .upToDate
            } catch {
                state = .failed
            }
        }
    }

    private static func fetchLatestVersion() async throws -> String {
        guard let url = URL(string: apiEndpoint) else {
            throw URLError(.badURL)
        }
        var request = URLRequest(url: url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        guard let tagName = json?["tag_name"] as? String else {
            throw URLError(.cannotParseResponse)
        }

        return tagName.hasPrefix("v") ? String(tagName.dropFirst()) : tagName
    }

    private static func isVersionNewer(_ a: String, than b: String) -> Bool {
        let partsA = a.split(separator: ".").compactMap { Int($0) }
        let partsB = b.split(separator: ".").compactMap { Int($0) }
        for i in 0..<max(partsA.count, partsB.count) {
            let va = i < partsA.count ? partsA[i] : 0
            let vb = i < partsB.count ? partsB[i] : 0
            if va != vb { return va > vb }
        }
        return false
    }
}
