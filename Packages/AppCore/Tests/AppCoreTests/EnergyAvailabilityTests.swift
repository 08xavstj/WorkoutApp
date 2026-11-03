import Foundation
import Testing
@testable import AppCore

struct EnergyAvailabilityTests {
    let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func week(intake: Double?, exercise: Double, days: Int = 7) -> [EnergyAvailability.Day] {
        (0..<days).map { EnergyAvailability.Day(date: start.addingTimeInterval(Double($0) * 86_400), intakeKcal: intake, exerciseKcal: exercise) }
    }

    @Test func formulaIsIntakeMinusExercisePerKgFatFreeMass() throws {
        // IOC 2023 / Loucks 2011: (intake − exercise) / FFM.
        let ffm = try #require(EnergyAvailability.fatFreeMass(bodyMassKg: 80, bodyFatPercent: 15))
        #expect(abs(ffm - 68) < 0.001)
        let value = try #require(EnergyAvailability.compute(intakeKcal: 2400, exerciseKcal: 500, fatFreeMassKg: ffm))
        #expect(abs(value - 1900 / 68) < 0.001)
        #expect(EnergyAvailability.compute(intakeKcal: 2400, exerciseKcal: 500, fatFreeMassKg: 0) == nil)
        #expect(EnergyAvailability.fatFreeMass(bodyMassKg: 80, bodyFatPercent: nil) == nil)
        #expect(EnergyAvailability.lowThreshold == 30)
        #expect(EnergyAvailability.adequate == 45)
    }

    @Test func flagsUnderThirtyOverTheWeek() throws {
        // 68 kg FFM: 1,900 kcal in, 400 out → 22 kcal/kg: low.
        let result = try #require(EnergyAvailability.assess(days: week(intake: 1900, exercise: 400), fatFreeMassKg: 68))
        #expect(result.isLow)
        #expect(result.loggedDays == 7)
        #expect(abs(result.kcalPerKgFFM - 1500 / 68) < 0.001)
        #expect(result.valueText == "22 kcal per kg fat-free mass")
        let message = try #require(EnergyAvailability.message(result, goals: Goals(weight: .lose)))
        #expect(message.contains("Ease the deficit"))
        #expect(EnergyAvailability.message(result, goals: Goals(weight: .maintain, focuses: [.endurance]))?.contains("carbs") == true)
        // 3,000 in, 500 out → 37: fine, no message.
        let fine = try #require(EnergyAvailability.assess(days: week(intake: 3000, exercise: 500), fatFreeMassKg: 68))
        #expect(!fine.isLow)
        #expect(EnergyAvailability.message(fine, goals: nil) == nil)
    }

    @Test func skipsUnloggedDaysAndNeedsFive() {
        var days = week(intake: 1900, exercise: 400)
        days[0].intakeKcal = nil
        days[1].intakeKcal = 0
        #expect(EnergyAvailability.assess(days: days, fatFreeMassKg: 68)?.loggedDays == 5)
        days[2].intakeKcal = nil
        #expect(EnergyAvailability.assess(days: days, fatFreeMassKg: 68) == nil)
        // Without body fat there's no fat-free mass, so no flag.
        #expect(EnergyAvailability.assess(days: week(intake: 1900, exercise: 400), fatFreeMassKg: nil) == nil)
    }

    @Test func usesOnlyTheLastSevenDays() throws {
        // Ten days: three starved early days, then seven fine ones → not low.
        let early = week(intake: 1200, exercise: 600, days: 3)
        let late = (3..<10).map { EnergyAvailability.Day(date: start.addingTimeInterval(Double($0) * 86_400), intakeKcal: 3000, exerciseKcal: 500) }
        let result = try #require(EnergyAvailability.assess(days: early + late, fatFreeMassKg: 68))
        #expect(!result.isLow)
        #expect(result.loggedDays == 7)
    }
}
