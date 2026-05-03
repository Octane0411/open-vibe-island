import Foundation
import CoreGraphics
import Testing
@testable import OpenIslandApp

@MainActor
struct CelebrationParticleMathTests {
    @Test
    func opacityIsOneAtStart() {
        #expect(abs(CelebrationParticles.opacity(elapsed: 0) - 1.0) < 0.001)
    }

    @Test
    func opacityIsZeroAtEnd() {
        #expect(CelebrationParticles.opacity(elapsed: 2.0) == 0)
    }

    @Test
    func opacityClampsBeyondEnd() {
        #expect(CelebrationParticles.opacity(elapsed: 5.0) == 0)
    }

    @Test
    func positionAdvancesOverTime() {
        let p0 = CelebrationParticles.position(seed: 5, elapsed: 0, anchor: .zero)
        let p1 = CelebrationParticles.position(seed: 5, elapsed: 1.0, anchor: .zero)
        #expect(p0 != p1)
    }

    @Test
    func positionIsDeterministicForSameSeed() {
        let a = CelebrationParticles.position(seed: 3, elapsed: 0.5, anchor: .zero)
        let b = CelebrationParticles.position(seed: 3, elapsed: 0.5, anchor: .zero)
        #expect(a == b)
    }
}
