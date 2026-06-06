import os
import Combine
import Foundation
import AppKit
import SwiftUI
import ScriptingBridge

class MusicSpotifyManager: MusicPlayerProtocol {
    var app: SpotifyApplication
    var notificationSubject: PassthroughSubject<MusicAlertItem, Never>

    var bundleId: String { MusicConstants.Spotify.bundleID }
    var appName: String { "Spotify" }
    var appPath: URL = URL(fileURLWithPath: "/Applications/Spotify.app")
    var appNotification: String { "\(bundleId).PlaybackStateChanged" }
    var defaultAlbumArt: NSImage { MusicAppIcons().getIcon(bundleID: bundleId) ?? NSImage() }

    var playerPosition: Double? { app.playerPosition }
    var isPlaying: Bool { app.playerState == .playing }
    var volume: CGFloat { CGFloat(app.soundVolume ?? 50) }
    var isLikeAuthorized: Bool = false
    var shuffleIsOn: Bool { app.shuffling ?? false }
    var shuffleContextEnabled: Bool { app.shufflingEnabled ?? false }
    var repeatContextEnabled: Bool { app.repeatingEnabled ?? false }
    var playbackSeekerEnabled: Bool { true }

    init(notificationSubject: PassthroughSubject<MusicAlertItem, Never>) {
        self.app = SBApplication(bundleIdentifier: MusicConstants.Spotify.bundleID) ?? SBApplication()
        self.notificationSubject = notificationSubject
    }

    func getTrackInfo() -> PlayerTrack {
        var track = PlayerTrack()
        track.title = app.currentTrack?.name ?? "Unknown Title"
        track.artist = app.currentTrack?.artist ?? "Unknown Artist"
        track.album = app.currentTrack?.album ?? "Unknown Artist"
        track.duration = CGFloat(app.currentTrack?.duration ?? 0) / 1000
        return track
    }

    func getAlbumArt(completion: @escaping @Sendable (MusicFetchedAlbumArt?) -> Void) {
        guard let urlString = app.currentTrack?.artworkUrl, let url = URL(string: urlString) else {
            completion(nil)
            return
        }
        URLSession.shared.dataTask(with: url) { data, _, error in
            guard error == nil, let data, let image = NSImage(data: data) else {
                DispatchQueue.main.async { completion(nil) }
                return
            }
            let fetched = MusicFetchedAlbumArt(image: Image(nsImage: image), nsImage: image)
            DispatchQueue.main.async {
                completion(fetched)
            }
        }.resume()
    }

    func playPause() { app.playpause?() }
    func previousTrack() { app.previousTrack?() }
    func nextTrack() { app.nextTrack?() }
    func toggleLoveTrack() -> Bool { false }

    func setShuffle(shuffleIsOn: Bool) -> Bool {
        app.setShuffling?(!shuffleIsOn)
        return !shuffleIsOn
    }

    func setRepeat(repeatIsOn: Bool) -> Bool {
        app.setRepeating?(!repeatIsOn)
        return !repeatIsOn
    }

    func getCurrentSeekerPosition() -> Double { Double(app.playerPosition ?? 0) }
    func seekTrack(seekerPosition: CGFloat) { app.setPlayerPosition?(Double(seekerPosition)) }
    func setVolume(volume: Int) { app.setSoundVolume?(volume) }

    func isRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleId }
    }
}
