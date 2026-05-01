import Foundation
import Testing
@testable import OpenIslandCore

struct CompanionPetTests {
    @Test
    func threeBuiltInPets() {
        #expect(CompanionPet.allCases.count == 3)
        #expect(CompanionPet.allCases.contains(.cat))
        #expect(CompanionPet.allCases.contains(.ghost))
        #expect(CompanionPet.allCases.contains(.robot))
    }

    @Test
    func rawValuesAreStable() {
        #expect(CompanionPet.cat.rawValue == "cat")
        #expect(CompanionPet.ghost.rawValue == "ghost")
        #expect(CompanionPet.robot.rawValue == "robot")
    }

    @Test
    func dailyHashIsStableWithinDay() {
        let day1 = Date(timeIntervalSince1970: 1_700_000_000)
        let pickA = CompanionPet.dailyPick(at: day1)
        let pickB = CompanionPet.dailyPick(at: day1.addingTimeInterval(3600))
        #expect(pickA == pickB)
    }

    @Test
    func dailyHashChangesAcrossDays() {
        let day1 = Date(timeIntervalSince1970: 1_700_000_000)
        let day2 = day1.addingTimeInterval(86_400 * 7)
        let pickA = CompanionPet.dailyPick(at: day1)
        let pickB = CompanionPet.dailyPick(at: day2)
        #expect(pickA != CompanionPet.dailyPick(at: day1.addingTimeInterval(86_400))
            || pickA != CompanionPet.dailyPick(at: day1.addingTimeInterval(86_400 * 2))
            || pickA != pickB)
    }

    @Test
    func pixelGridParsesAsciiCorrectly() {
        let grid = PixelPetSprite.parseGrid("""
        .X.
        XXX
        .X.
        """)
        #expect(grid.count == 3)
        #expect(grid[0] == [false, true, false])
        #expect(grid[1] == [true, true, true])
        #expect(grid[2] == [false, true, false])
    }

    @Test
    func pixelGridSkipsBlankLines() {
        let grid = PixelPetSprite.parseGrid("""

        XX

        """)
        #expect(grid.count == 1)
        #expect(grid[0] == [true, true])
    }

    @Test
    func pixelGridUsesTrailingShorterRow() {
        let grid = PixelPetSprite.parseGrid("""
        XX
        X
        """)
        #expect(grid[0].count == 2)
        #expect(grid[1].count == 1)
    }

    @Test
    func eachPetHasFramesForEveryState() {
        for pet in CompanionPet.allCases {
            for state in CompanionState.allCases {
                let frames = PetSpriteData.frames(for: pet, state: state)
                #expect(!frames.isEmpty, "\(pet)/\(state) has no frames")
                #expect(frames.allSatisfy { !$0.isEmpty }, "\(pet)/\(state) has empty frame")
            }
        }
    }
}
