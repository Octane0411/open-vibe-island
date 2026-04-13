import SwiftUI
import AppKit
import OpenIslandCore

struct MediaStripView: View {
    let state: NowPlayingState
    let artworkCache: ArtworkCache

    @State private var dominantColor: Color = .gray

    private var artworkImage: NSImage? {
        guard let url = state.artworkURL else { return nil }
        return artworkCache.image(for: url)
    }

    var body: some View {
        HStack(spacing: 12) {
            albumArt
            trackInfo
            Spacer(minLength: 0)
            controls
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(coloredBackground)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .onChange(of: artworkCache.version) { _, _ in updateDominantColor() }
        .onChange(of: state.artworkURL) { _, url in
            if let url { artworkCache.prefetch(url) }
            updateDominantColor()
        }
        .onAppear {
            if let url = state.artworkURL { artworkCache.prefetch(url) }
            updateDominantColor()
        }
    }

    // MARK: Subviews

    private var albumArt: some View {
        Group {
            if let img = artworkImage {
                Image(nsImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.white.opacity(0.1))
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 16))
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .frame(width: 48, height: 48)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .animation(.easeInOut(duration: 0.3), value: artworkImage != nil)
    }

    private var trackInfo: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(state.title ?? "Not Playing")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            if let artist = state.artist {
                Text(artist)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let album = state.album {
                Text(album)
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 8) {
            Button { PlaybackController.previous() } label: {
                Image(systemName: "backward.fill")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)

            Button { PlaybackController.playPause() } label: {
                Image(systemName: state.isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 15))
            }
            .buttonStyle(.plain)

            Button { PlaybackController.next() } label: {
                Image(systemName: "forward.fill")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.primary)
    }

    private var coloredBackground: some View {
        ZStack {
            dominantColor.opacity(0.15)
            Color.white.opacity(0.04)
        }
    }

    // MARK: Helpers

    private func updateDominantColor() {
        dominantColor = DominantColorExtractor.extractOrFallback(from: artworkImage)
    }
}
