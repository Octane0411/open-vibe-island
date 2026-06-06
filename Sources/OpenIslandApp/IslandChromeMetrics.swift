import CoreGraphics

enum IslandChromeMetrics {
    static let openedShadowHorizontalInset: CGFloat = 18
    static let openedShadowBottomInset: CGFloat = 22
    static let closedShadowHorizontalInset: CGFloat = 12
    static let closedShadowBottomInset: CGFloat = 14
    static let closedHoverScale: CGFloat = 1.028
    static let notchedClosedMinimumWingReserve: CGFloat = 44
    static let notchedClosedHorizontalPadding: CGFloat = 14
    /// Outer leading inset before album art on closed music surfaces.
    static let notchedMusicLeadingPadding: CGFloat = 10
    /// Trailing outer inset after play icon / waveform on closed music surfaces.
    static let notchedMusicTrailingPadding: CGFloat = 8
    static let notchedClosedContentGap: CGFloat = 8

    /// Total outer width of a compact music pill on a notched MacBook.
    static func notchedCompactMusicOuterWidth(physicalNotchWidth: CGFloat) -> CGFloat {
        notchedCompactMusicLeftWingReserve()
            + physicalNotchWidth
            + notchedCompactMusicRightWingReserve()
    }

    /// Left wing for compact music — outer leading inset plus album art against the notch.
    static func notchedCompactMusicLeftWingReserve() -> CGFloat {
        notchedMusicLeadingPadding + MusicTrackNotificationMetrics.albumArtWidth
    }

    /// Right wing for compact music — waveform against the notch, trailing outer inset.
    static func notchedCompactMusicRightWingReserve() -> CGFloat {
        let waveformWidth: CGFloat = 20
        return ceil(waveformWidth + notchedMusicTrailingPadding)
    }

    static func notchedClosedWingReserve(rightSlotWidth: CGFloat = 0) -> CGFloat {
        let glyphWidth: CGFloat = 24
        let requiredContentWidth = max(glyphWidth, rightSlotWidth)
        let requiredReserve = requiredContentWidth
            + notchedClosedHorizontalPadding
            + notchedClosedContentGap
        return max(notchedClosedMinimumWingReserve, ceil(requiredReserve))
    }

    /// Max left-wing width before the notch-anchored pill extends past the panel edge.
    static func notchedMusicNotificationMaxLeftWingReserve(
        panelContentWidth: CGFloat,
        physicalNotchWidth: CGFloat
    ) -> CGFloat {
        guard panelContentWidth > 0 else { return .greatestFiniteMagnitude }
        return max(0, floor(panelContentWidth / 2 - physicalNotchWidth / 2))
    }

    private static let notchedMusicNotificationFixedLeftChromeWidth: CGFloat =
        notchedMusicLeadingPadding
            + MusicTrackNotificationMetrics.albumArtWidth
            + notchedClosedContentGap

    /// Left wing for music notifications — album art plus stacked title/artist.
    static func notchedMusicNotificationLeftWingReserve(
        title: String,
        artist: String,
        panelContentWidth: CGFloat = .greatestFiniteMagnitude,
        physicalNotchWidth: CGFloat = 0
    ) -> CGFloat {
        let textReserve = MusicTrackNotificationMetrics.estimatedTextBlockWidth(
            title: title,
            artist: artist
        )
        let required = notchedMusicNotificationFixedLeftChromeWidth + textReserve
        let ideal = ceil(required)
        guard physicalNotchWidth > 0, panelContentWidth < .greatestFiniteMagnitude else {
            return ideal
        }
        return min(ideal, notchedMusicNotificationMaxLeftWingReserve(
            panelContentWidth: panelContentWidth,
            physicalNotchWidth: physicalNotchWidth
        ))
    }

    /// Right wing for music notifications — play/pause icon pinned to the outer edge.
    static func notchedMusicNotificationRightWingReserve() -> CGFloat {
        let playWidth: CGFloat = 18
        return ceil(notchedMusicTrailingPadding + playWidth)
    }

    static func notchedMusicNotificationLeftTextWidth(
        title: String,
        artist: String,
        panelContentWidth: CGFloat = .greatestFiniteMagnitude,
        physicalNotchWidth: CGFloat = 0
    ) -> CGFloat {
        let leftWing = notchedMusicNotificationLeftWingReserve(
            title: title,
            artist: artist,
            panelContentWidth: panelContentWidth,
            physicalNotchWidth: physicalNotchWidth
        )
        let available = leftWing - notchedMusicNotificationFixedLeftChromeWidth
        let desired = MusicTrackNotificationMetrics.estimatedTextBlockWidth(
            title: title,
            artist: artist
        )
        return min(desired, max(MusicTrackNotificationMetrics.minimumTextWidth, available))
    }
}
