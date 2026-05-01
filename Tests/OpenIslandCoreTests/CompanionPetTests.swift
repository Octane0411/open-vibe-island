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
}
