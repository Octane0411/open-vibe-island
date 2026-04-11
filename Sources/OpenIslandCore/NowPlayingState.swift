import Foundation

public struct NowPlayingState: Equatable, Codable, Sendable {
    public var title: String?
    public var artist: String?
    public var album: String?
    public var artworkData: Data?
    public var isPlaying: Bool

    public init(
        title: String?,
        artist: String?,
        album: String?,
        artworkData: Data?,
        isPlaying: Bool
    ) {
        self.title = title
        self.artist = artist
        self.album = album
        self.artworkData = artworkData
        self.isPlaying = isPlaying
    }

    public static let none = NowPlayingState(
        title: nil, artist: nil, album: nil, artworkData: nil, isPlaying: false
    )

    public var hasContent: Bool {
        title != nil || artist != nil
    }

    public var displayLine: String {
        switch (title, artist) {
        case let (t?, a?): return "\(t) — \(a)"
        case let (t?, nil): return t
        case let (nil, a?): return a
        default: return "Unknown"
        }
    }
}
