import os
import Combine
import Foundation
import AppKit
import ScriptingBridge
import SwiftUI

class MusicAppleMusicManager: MusicPlayerProtocol {
    var app: MusicApplication = SBApplication(bundleIdentifier: MusicConstants.AppleMusic.bundleID)!
    var notificationSubject: PassthroughSubject<MusicAlertItem, Never>

    var bundleId: String { MusicConstants.AppleMusic.bundleID }
    var appName: String { "Apple Music" }
    var appPath: URL = URL(fileURLWithPath: "/System/Applications/Music.app")
    var appNotification: String { "\(bundleId).playerInfo" }
    var defaultAlbumArt: NSImage { MusicAppIcons().getIcon(bundleID: bundleId) ?? NSImage() }

    var playerPosition: Double? { app.playerPosition }
    var isPlaying: Bool { app.playerState == .playing }
    var volume: CGFloat { CGFloat(app.soundVolume ?? 50) }
    var isLikeAuthorized: Bool = true
    var shuffleIsOn: Bool { app.shuffleEnabled ?? false }
    var shuffleContextEnabled: Bool = true
    var repeatContextEnabled: Bool = true
    var playbackSeekerEnabled: Bool = true

    init(notificationSubject: PassthroughSubject<MusicAlertItem, Never>) {
        self.notificationSubject = notificationSubject
    }

    func getAlbumArt(completion: @escaping @Sendable (MusicFetchedAlbumArt?) -> Void) {
        guard let currentTrack = app.currentTrack else {
            completion(nil)
            return
        }
        let expectedTitle = currentTrack.name ?? ""
        let expectedArtist = currentTrack.artist ?? ""
        let expectedAlbum = currentTrack.album ?? ""

        guard let art = currentTrack.artworks?()[0] as? MusicArtwork else {
            completion(nil)
            return
        }
        // ScriptingBridge can return NSAppleEventDescriptor typed as NSImage when art isn't ready
        guard let rawData = art.data, rawData.isKind(of: NSImage.self), !rawData.musicIsEmpty() else {
            completion(nil)
            return
        }
        guard let liveTrack = app.currentTrack,
              liveTrack.name == expectedTitle,
              liveTrack.artist == expectedArtist,
              liveTrack.album == expectedAlbum else {
            completion(nil)
            return
        }
        completion(MusicFetchedAlbumArt(image: Image(nsImage: rawData), nsImage: rawData))
    }

    func getTrackInfo() -> PlayerTrack {
        var track = PlayerTrack()
        track.title = app.currentTrack?.name ?? "Unknown Title"
        track.artist = app.currentTrack?.artist ?? "Unknown Artist"
        track.album = app.currentTrack?.album ?? "Unknown Album"
        track.isLoved = getIsLoved()
        track.duration = CGFloat(app.currentTrack?.duration ?? 0)
        return track
    }

    func playPause() { app.playpause?() }
    func previousTrack() { app.backTrack?() }
    func nextTrack() { app.nextTrack?() }

    func toggleLoveTrack() -> Bool {
        if let loved = app.currentTrack?.loved {
            app.currentTrack?.setLoved?(!loved)
            return !loved
        } else if let favorited = app.currentTrack?.favorited {
            app.currentTrack?.setFavorited?(!favorited)
            return !favorited
        }
        sendNotification(title: "Error", message: "Could not save track to favorites")
        return false
    }

    func setShuffle(shuffleIsOn: Bool) -> Bool {
        app.setShuffleEnabled?(!shuffleIsOn)
        return !shuffleIsOn
    }

    func setRepeat(repeatIsOn: Bool) -> Bool {
        let mode: MusicERpt = repeatIsOn ? .off : .all
        app.setSongRepeat?(mode)
        return !repeatIsOn
    }

    func getCurrentSeekerPosition() -> Double { Double(app.playerPosition ?? 0) }
    func seekTrack(seekerPosition: CGFloat) { app.setPlayerPosition?(seekerPosition) }
    func setVolume(volume: Int) { app.setSoundVolume?(volume) }

    func isRunning() -> Bool {
        NSWorkspace.shared.runningApplications.contains { $0.bundleIdentifier == bundleId }
    }

    private func getIsLoved() -> Bool {
        if let loved = app.currentTrack?.loved { return loved }
        if let favorited = app.currentTrack?.favorited { return favorited }
        return false
    }
}
