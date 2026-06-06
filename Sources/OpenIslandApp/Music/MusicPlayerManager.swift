import os
import SwiftUI
import Combine
import Observation

let musicConnectedAppDefaultsKey = "music.connectedApp"

@MainActor
@Observable
final class MusicPlayerManager {
    static let connectedAppKey = musicConnectedAppDefaultsKey
    static let noPlaybackPositionPlaceholder = "--:--"

    private var musicApp: (any MusicPlayerProtocol)!
    private var playerAppProvider: MusicPlayerAppProvider!

    var name: String { musicApp.appName }
    var isRunning: Bool { musicApp.isRunning() }

    let notificationSubject = PassthroughSubject<MusicAlertItem, Never>()

    // Track state
    var track = PlayerTrack()
    var isPlaying = false
    var isLoved = false

    // Seeker
    var seekerPosition: CGFloat = 0
    var isDraggingPlaybackPositionView = false

    // Playback settings
    var shuffleIsOn = false
    var shuffleContextEnabled = false
    var repeatIsOn = false
    var repeatContextEnabled = false

    // Playback time
    var formattedDuration = MusicPlayerManager.noPlaybackPositionPlaceholder
    var formattedPlaybackPosition = MusicPlayerManager.noPlaybackPositionPlaceholder

    // Volume
    var volume: CGFloat = 50.0
    var isDraggingSoundVolumeSlider = false

    // Audio devices
    var audioDevices = MusicAudioDevice.output.filter { $0.transportType != .virtual }

    // Connected app name for display
    var connectedAppName: String { musicApp.appName }

    var onTrackChange: ((PlayerTrack) -> Void)?
    var onPlaybackStateChange: ((Bool) -> Void)?
    var onAlbumArtUpdated: ((PlayerTrack) -> Void)?

    @ObservationIgnored private var cancellables = Set<AnyCancellable>()
    @ObservationIgnored private var timerCancellable: AnyCancellable?
    @ObservationIgnored private var userDefaultsObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var albumArtFetchGeneration: UInt64 = 0

    init() {
        playerAppProvider = MusicPlayerAppProvider(notificationSubject: notificationSubject)
        setupMusicApp()
        playStateOrTrackDidChange(nil)
    }

    // MARK: - Setup

    private func setupMusicApp() {
        musicApp = playerAppProvider.getPlayerApp()
        setupObservers()
    }

    func setupObservers() {
        cleanupObservers()

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(playStateOrTrackDidChange),
            name: NSNotification.Name(rawValue: musicApp.appNotification),
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        userDefaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.handleConnectedAppChange()
            }
        }
    }

    private func cleanupObservers() {
        DistributedNotificationCenter.default().removeObserver(self)
        cancellables.removeAll()
        if let userDefaultsObserver {
            NotificationCenter.default.removeObserver(userDefaultsObserver)
        }
        userDefaultsObserver = nil
    }

    private func handleConnectedAppChange() {
        let currentApp = UserDefaults.standard.string(forKey: musicConnectedAppDefaultsKey) ?? "none"
        let newAppName: String
        switch currentApp {
        case "spotify":    newAppName = "Spotify"
        case "appleMusic": newAppName = "Apple Music"
        default:           newAppName = "None"
        }
        guard newAppName != connectedAppName else { return }
        setupMusicApp()
        playStateOrTrackDidChange(nil)
    }

    // MARK: - Notification handlers

    @objc func playStateOrTrackDidChange(_ sender: NSNotification?) {
        let musicAppKilled = sender?.userInfo?["Player State"] as? String == "Stopped"
        let isRunningFromNotification = !musicAppKilled && isRunning

        if musicAppKilled || !musicApp.isRunning() {
            track = PlayerTrack()
            timerCancellable?.cancel()
            timerCancellable = nil
            return
        }

        getPlayState()
        updateFormattedDuration()

        let notificationTrack = musicApp.getTrackInfo()
        if track == notificationTrack { return }

        getPlaybackSettingInfo()
        getNewSongInfo()
        onTrackChange?(track)
        _ = isRunningFromNotification
    }

    // MARK: - Media & Playback

    private func getPlayState() {
        let current = musicApp.isPlaying
        if current != isPlaying {
            isPlaying = current
            onPlaybackStateChange?(isPlaying)
        }
    }

    func getPlaybackSettingInfo() {
        shuffleIsOn = musicApp.shuffleIsOn
        shuffleContextEnabled = musicApp.shuffleContextEnabled
        repeatContextEnabled = musicApp.repeatContextEnabled
    }

    func getNewSongInfo() {
        let polled = musicApp.getTrackInfo()
        var updatedPolled = polled
        updatedPolled.clearAlbumArt()

        withAnimation(MusicConstants.mainAnimation) {
            getCurrentSeekerPosition()
            track = updatedPolled
        }
        fetchAlbumArt(for: updatedPolled)
        updateFormattedDuration()
    }

    func fetchAlbumArt(for expectedTrack: PlayerTrack? = nil, retryCount: Int = 5) {
        albumArtFetchGeneration &+= 1
        let generation = albumArtFetchGeneration
        let expected = expectedTrack ?? track

        musicApp.getAlbumArt { result in
            Task { @MainActor [weak self] in
                guard let self else { return }
                guard generation == self.albumArtFetchGeneration else { return }
                guard self.track.matchesMetadata(expected) else { return }

                if let result {
                    self.updateAlbumArt(newAlbumArt: result)
                } else if retryCount > 0 {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard generation == self.albumArtFetchGeneration else { return }
                    guard self.track.matchesMetadata(expected) else { return }
                    self.fetchAlbumArt(for: expected, retryCount: retryCount - 1)
                }
            }
        }
    }

    func updateAlbumArt(newAlbumArt: MusicFetchedAlbumArt) {
        withAnimation {
            track.avgAlbumColor = Color(nsColor: newAlbumArt.nsImage.musicAverageColor ?? .gray)
            track.nsAlbumArt = newAlbumArt.nsImage
            track.albumArt = newAlbumArt.image
        }
        onAlbumArtUpdated?(track)
    }

    // MARK: - Controls

    func togglePlayPause() {
        isPlaying = !isPlaying
        musicApp.playPause()
        onPlaybackStateChange?(isPlaying)
    }

    func previousTrack() {
        if track.isPodcast {
            seekerPosition = seekerPosition - MusicConstants.podcastRewindDurationSec
            seekTrack()
        } else {
            musicApp.previousTrack()
        }
    }

    func nextTrack() {
        if track.isPodcast {
            seekerPosition = seekerPosition + MusicConstants.podcastRewindDurationSec
            seekTrack()
        } else {
            musicApp.nextTrack()
        }
    }

    func toggleLoveTrack() { isLoved = musicApp.toggleLoveTrack() }
    func setShuffle() { shuffleIsOn = musicApp.setShuffle(shuffleIsOn: shuffleIsOn) }
    func setRepeat() { repeatIsOn = musicApp.setRepeat(repeatIsOn: repeatIsOn) }

    // MARK: - Seeker

    func getCurrentSeekerPosition() {
        guard musicApp.isRunning(), !isDraggingPlaybackPositionView else { return }
        seekerPosition = musicApp.getCurrentSeekerPosition()
        updateFormattedPlaybackPosition()
    }

    func seekTrack() { musicApp.seekTrack(seekerPosition: seekerPosition) }

    func updateFormattedPlaybackPosition() {
        guard musicApp.playerPosition != nil, !isDraggingPlaybackPositionView else { return }
        formattedPlaybackPosition = formattedTimestamp(seekerPosition)
    }

    func updateFormattedDuration() { formattedDuration = formattedTimestamp(track.duration) }

    func draggingPlaybackPosition() { formattedPlaybackPosition = formattedTimestamp(seekerPosition) }

    // MARK: - Timer

    func startTimer() {
        guard musicApp.isRunning() else { return }
        timerCancellable?.cancel()
        timerCancellable = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                self?.getVolume()
                self?.getCurrentSeekerPosition()
                self?.getPlaybackSettingInfo()
                self?.pollForTrackChanges()
            }
    }

    func stopTimer() {
        timerCancellable?.cancel()
        timerCancellable = nil
    }

    private func pollForTrackChanges() {
        guard musicApp.isRunning() else { return }
        let current = musicApp.isPlaying
        if current != isPlaying {
            isPlaying = current
            onPlaybackStateChange?(isPlaying)
        }
        let polled = musicApp.getTrackInfo()
        guard polled.title != track.title || polled.artist != track.artist ||
              polled.album != track.album || polled.duration != track.duration else { return }
        
        var updatedPolled = polled
        updatedPolled.clearAlbumArt()

        withAnimation(MusicConstants.mainAnimation) {
            track = updatedPolled
        }
        onTrackChange?(updatedPolled)
        updateFormattedDuration()
        fetchAlbumArt(for: updatedPolled)
    }

    // MARK: - Volume

    func getVolume() { volume = musicApp.volume }

    func setVolume(newVolume: Int) {
        var clamped = newVolume
        if clamped > 100 { clamped = 100 }
        if clamped < 0 { clamped = 0 }
        musicApp.setVolume(volume: clamped)
        withAnimation { volume = CGFloat(clamped) }
    }

    func increaseVolume() { setVolume(newVolume: Int(volume) + 10) }
    func decreaseVolume() { setVolume(newVolume: Int(volume) - 10) }

    // MARK: - Audio device

    func setOutputDevice(audioDevice: MusicAudioDevice) {
        do {
            try MusicAudioDevice.setDefaultDevice(for: .output, device: audioDevice)
        } catch {
            notificationSubject.send(MusicAlertItem(title: "Audio device not set", message: "Error setting output device"))
        }
    }

    // MARK: - Open music app

    func openMusicApp() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: musicApp.appPath, configuration: configuration)
    }

    // MARK: - Connected app

    func switchToAppleMusic() {
        UserDefaults.standard.set("appleMusic", forKey: Self.connectedAppKey)
    }

    func switchToSpotify() {
        UserDefaults.standard.set("spotify", forKey: Self.connectedAppKey)
    }

    var isMusicEnabled: Bool { connectedAppName != "None" }

    var isSpotifyAvailable: Bool {
        FileManager.default.fileExists(atPath: "/Applications/Spotify.app")
    }

    // MARK: - Helpers

    func isLikeAuthorized() -> Bool { musicApp.isLikeAuthorized }

    private func formattedTimestamp(_ number: CGFloat) -> String {
        let formatter: DateComponentsFormatter = number >= 3600
            ? .musicPlaybackTimeWithHours : .musicPlaybackTime
        return formatter.string(from: Double(number)) ?? Self.noPlaybackPositionPlaceholder
    }
}

