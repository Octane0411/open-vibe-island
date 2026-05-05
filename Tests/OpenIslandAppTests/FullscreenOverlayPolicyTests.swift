import Testing
@testable import OpenIslandApp

struct FullscreenOverlayPolicyTests {
    @Test
    func suppressOnlyWhenEnabledAndFullscreenAndNoAttention() {
        // (hideEnabled, isFullscreen, hasAttention) -> expectedSuppress
        let cases: [(Bool, Bool, Bool, Bool)] = [
            (false, false, false, false),
            (false, false, true,  false),
            (false, true,  false, false),
            (false, true,  true,  false),
            (true,  false, false, false),
            (true,  false, true,  false),
            (true,  true,  false, true),   // the only case that suppresses
            (true,  true,  true,  false),
        ]
        for (enabled, fs, attention, expected) in cases {
            let actual = AppModel.shouldSuppressOverlayForFullscreen(
                hideInFullscreenEnabled: enabled,
                isOverlayScreenFullscreen: fs,
                hasAttentionRequiredSession: attention
            )
            #expect(actual == expected, "enabled=\(enabled) fs=\(fs) attention=\(attention)")
        }
    }
}
