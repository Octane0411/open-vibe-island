import Foundation
import Observation
import OpenIslandCore

@MainActor
@Observable
final class NowPlayingObserver {
    private(set) var state: NowPlayingState = .none
    private var timer: Timer?
    private let pollInterval: TimeInterval

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
            if player state is playing then
                return "playing" & sep & (name of current track) & sep & (artist of current track) & sep & (album of current track)
            else
                return "paused" & sep & (name of current track) & sep & (artist of current track) & sep & (album of current track)
            end if
        end tell
        """
        return parseMediaScript(script)
    }

    private func pollMusic() -> NowPlayingState? {
        let script = """
        tell application "Music"
            if not (it is running) then return ""
            set sep to ASCII character 31
            if player state is playing then
                return "playing" & sep & (name of current track) & sep & (artist of current track) & sep & (album of current track)
            else
                return "paused" & sep & (name of current track) & sep & (artist of current track) & sep & (album of current track)
            end if
        end tell
        """
        return parseMediaScript(script)
    }

    private func parseMediaScript(_ script: String) -> NowPlayingState? {
        guard let raw = runOsascript(script), !raw.isEmpty else { return nil }
        let sep = String(UnicodeScalar(31)!)
        let parts = raw.components(separatedBy: sep)
        guard parts.count >= 4 else { return nil }
        return NowPlayingState(
            title: parts[1].nilIfEmpty,
            artist: parts[2].nilIfEmpty,
            album: parts[3].nilIfEmpty,
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
