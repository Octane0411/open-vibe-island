import SwiftUI

struct MusicPanelView: View {
    @Bindable var playerManager: MusicPlayerManager

    var body: some View {
        if playerManager.isMusicEnabled {
            musicControls
        } else {
            musicDisabledPlaceholder
        }
    }

    private var musicControls: some View {
        HStack(spacing: 20) {
            MusicAlbumArtView(playerManager: playerManager, imageSize: 180)

            VStack(spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    PlayerTrackDetailsView(playerManager: playerManager)
                    
                    Image(systemName: playerManager.isPlaying ? "play.fill" : "pause.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(playerManager.track.avgAlbumColor)
                        .frame(width: 20, height: 20)
                }

                MusicPlaybackButtonsView(playerManager: playerManager, buttonSize: 22, spacing: 20)

                VStack(spacing: 12) {
                    MusicPlaybackPositionView(playerManager: playerManager)
                }
                .padding(.horizontal, 8)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 24)
        .padding(.top, 16)
        .padding(.bottom, 10)
        .onAppear {
            playerManager.startTimer()
            playerManager.getVolume()
        }
        .onDisappear {
            playerManager.stopTimer()
        }
    }

    private var musicDisabledPlaceholder: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "music.note.list")
                .font(.system(size: 28, weight: .light))
                .foregroundStyle(.white.opacity(0.25))
            Text("No music player selected")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
            Text("Choose Apple Music or Spotify in Settings → Music")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.25))
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 16)
    }
}
