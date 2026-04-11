import Testing
import Foundation
@testable import OpenIslandCore

@Suite("NowPlayingState")
struct NowPlayingStateTests {
    @Test func codableRoundTrip() throws {
        let state = NowPlayingState(
            title: "Bohemian Rhapsody",
            artist: "Queen",
            album: "A Night at the Opera",
            artworkData: nil,
            isPlaying: true
        )
        let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(NowPlayingState.self, from: data)
        #expect(decoded == state)
    }

    @Test func equalityRequiresIsPlaying() {
        let a = NowPlayingState(title: "Track", artist: "Artist", album: nil, artworkData: nil, isPlaying: true)
        let b = NowPlayingState(title: "Track", artist: "Artist", album: nil, artworkData: nil, isPlaying: false)
        #expect(a != b)
    }

    @Test func noneStateIsEmpty() {
        let none = NowPlayingState.none
        #expect(none.title == nil)
        #expect(none.artist == nil)
        #expect(!none.isPlaying)
        #expect(!none.hasContent)
    }

    @Test func displayLineFormats() {
        let both = NowPlayingState(title: "Song", artist: "Band", album: nil, artworkData: nil, isPlaying: false)
        #expect(both.displayLine == "Song — Band")

        let titleOnly = NowPlayingState(title: "Song", artist: nil, album: nil, artworkData: nil, isPlaying: false)
        #expect(titleOnly.displayLine == "Song")

        let artistOnly = NowPlayingState(title: nil, artist: "Band", album: nil, artworkData: nil, isPlaying: false)
        #expect(artistOnly.displayLine == "Band")

        #expect(NowPlayingState.none.displayLine == "Unknown")
    }
}
