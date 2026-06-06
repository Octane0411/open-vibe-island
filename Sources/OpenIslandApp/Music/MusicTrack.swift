import SwiftUI

struct PlayerTrack: Equatable {
    var title: String = ""
    var artist: String = ""
    var album: String = ""
    var albumArt: Image = Image(systemName: "music.note")
    var nsAlbumArt: NSImage = NSImage()
    var avgAlbumColor: Color = .gray
    var duration: CGFloat = 0.0
    var isLoved: Bool = false

    var isPodcast: Bool { self.duration > MusicConstants.podcastThresholdDurationSec }

    static func == (lhs: PlayerTrack, rhs: PlayerTrack) -> Bool {
        if lhs.title == "" && lhs.artist == "" && lhs.album == "" { return false }
        return lhs.title == rhs.title && lhs.artist == rhs.artist && lhs.album == rhs.album
    }

    func isEmpty() -> Bool {
        title == "" && artist == "" && album == ""
    }

    func matchesMetadata(_ other: PlayerTrack) -> Bool {
        title == other.title && artist == other.artist && album == other.album
    }

    mutating func clearAlbumArt() {
        albumArt = Image(systemName: "music.note")
        nsAlbumArt = NSImage()
        avgAlbumColor = .gray
    }
}
