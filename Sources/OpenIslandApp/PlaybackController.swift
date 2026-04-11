import Foundation

enum PlaybackController {
    static func playPause() {
        runSpotify("playpause")
        runMusic("playpause")
    }

    static func next() {
        runSpotify("next track")
        runMusic("next track")
    }

    static func previous() {
        runSpotify("previous track")
        runMusic("previous track")
    }

    // MARK: Private

    private static func runSpotify(_ command: String) {
        run("tell application \"Spotify\" to if it is running then \(command)")
    }

    private static func runMusic(_ command: String) {
        run("tell application \"Music\" to if it is running then \(command)")
    }

    private static func run(_ script: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        process.arguments = ["-e", script]
        process.standardOutput = Pipe()
        process.standardError = Pipe()
        try? process.run()
    }
}
