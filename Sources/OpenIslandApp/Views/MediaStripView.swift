import SwiftUI
import OpenIslandCore

struct MediaStripView: View {
    let state: NowPlayingState

    var body: some View {
        HStack(spacing: 10) {
            // Album art placeholder
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.white.opacity(0.1))
                .frame(width: 32, height: 32)
                .overlay {
                    Image(systemName: "music.note")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }

            // Title + artist
            VStack(alignment: .leading, spacing: 1) {
                Text(state.title ?? "Not Playing")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(1)
                if let artist = state.artist {
                    Text(artist)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Playback controls
            HStack(spacing: 6) {
                Button {
                    PlaybackController.previous()
                } label: {
                    Image(systemName: "backward.fill")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)

                Button {
                    PlaybackController.playPause()
                } label: {
                    Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 13))
                }
                .buttonStyle(.plain)

                Button {
                    PlaybackController.next()
                } label: {
                    Image(systemName: "forward.fill")
                        .font(.system(size: 11))
                }
                .buttonStyle(.plain)
            }
            .foregroundStyle(.primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
