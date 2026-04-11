import Foundation
import Observation
import OpenIslandCore

@MainActor
@Observable
final class NowPlayingObserver {
    private(set) var state: NowPlayingState = .none
    private var timer: Timer?
    private let pollInterval: TimeInterval
    private var lastMusicTrackKey: String = ""

    private static let musicArtworkPath: String = {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        return (caches ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent("open-island-artwork")
            .path
    }()

    init(pollInterval: TimeInterval = 1.0) {
        self.pollInterval = pollInterval
    }

    func start() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.poll() }
        }
        poll()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        state = .none
    }

    // MARK: Private

    private func poll() {
        if let s = pollSpotify() { state = s; return }
        if let s = pollMusic() { state = s; return }
        state = .none
    }

    private func pollSpotify() -> NowPlayingState? {
        let script = """
        tell application "Spotify"
            if not (it is running) then return ""
            set sep to ASCII character 31
            set isPlaying to player state is playing
            set status to "paused"
            if isPlaying then set status to "playing"
            set artURL to ""
            try
                set artURL to artwork url of current track
            end try
            return status & sep & (name of current track) & sep & (artist of current track) & sep & (album of current track) & sep & artURL
        end tell
        """
        return parseSpotifyScript(script)
    }

    private func pollMusic() -> NowPlayingState? {
        let script = """
        tell application "Music"
            if not (it is running) then return ""
            set sep to ASCII character 31
            if player state is stopped then return ""
            set status to "paused"
            if player state is playing then set status to "playing"
            return status & sep & (name of current track) & sep & (artist of current track) & sep & (album of current track)
        end tell
        """
        guard let raw = runOsascript(script), !raw.isEmpty else { return nil }
        let sep = String(UnicodeScalar(31)!)
        let parts = raw.components(separatedBy: sep)
        guard parts.count >= 4 else { return nil }

        let title = parts[1].nilIfEmpty
        let artist = parts[2].nilIfEmpty
        let album = parts[3].nilIfEmpty
        let trackKey = "\(title ?? "")-\(artist ?? "")"

        // Only write artwork to disk when the track changes.
        var artworkURL: URL? = nil
        if trackKey != lastMusicTrackKey {
            lastMusicTrackKey = trackKey
            if let url = writeMusicArtwork() {
                artworkURL = url
            } else {
                // Write failed — remove stale file so we don't serve previous track's art
                try? FileManager.default.removeItem(atPath: Self.musicArtworkPath)
            }
        } else if FileManager.default.fileExists(atPath: Self.musicArtworkPath) {
            artworkURL = URL(fileURLWithPath: Self.musicArtworkPath)
        }

        return NowPlayingState(
            title: title,
            artist: artist,
            album: album,
            artworkURL: artworkURL,
            artworkData: nil,
            isPlaying: parts[0] == "playing"
        )
    }

    private func writeMusicArtwork() -> URL? {
        let script = """
        tell application "Music"
            if not (it is running) then return ""
            if player state is stopped then return ""
            try
                set artData to raw data of artwork 1 of current track
                set tmpPath to "\(Self.musicArtworkPath)"
                set fileRef to open for access POSIX file tmpPath with write permission
                set eof of fileRef to 0
                write artData to fileRef
                close access fileRef
                return tmpPath
            on error
                return ""
            end try
        end tell
        """
        guard let path = runOsascript(script), !path.isEmpty else { return nil }
        return URL(fileURLWithPath: path)
    }

    private func parseSpotifyScript(_ script: String) -> NowPlayingState? {
        guard let raw = runOsascript(script), !raw.isEmpty else { return nil }
        let sep = String(UnicodeScalar(31)!)
        let parts = raw.components(separatedBy: sep)
        guard parts.count >= 4 else { return nil }
        let artworkURL = parts.count >= 5 ? URL(string: parts[4].trimmingCharacters(in: .whitespaces)) : nil
        return NowPlayingState(
            title: parts[1].nilIfEmpty,
            artist: parts[2].nilIfEmpty,
            album: parts[3].nilIfEmpty,
            artworkURL: artworkURL,
            artworkData: nil,
            isPlaying: parts[0] == "playing"
        )
    }

    private func runOsascript(_ script: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        do { try process.run(); process.waitUntilExit() } catch { return nil }
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}
