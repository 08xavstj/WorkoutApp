import Foundation
import Testing
@testable import AppCore

struct AlcoholTests {
    @Test func standardServingsAreAboutOneDrink() {
        let beer = AlcoholEntry(kind: .beer, millilitres: 355)
        let wine = AlcoholEntry(kind: .wine, millilitres: 148)
        let shot = AlcoholEntry(kind: .spirits, millilitres: 44)
        for entry in [beer, wine, shot] {
            #expect(abs(entry.standardDrinks - 1) < 0.05)
        }
    }

    @Test func strongerOrBiggerDrinksCountMore() {
        let pintOfIPA = AlcoholEntry(kind: .strongBeer, millilitres: 473)
        #expect(pintOfIPA.standardDrinks > 1.8)
        let custom = AlcoholEntry(kind: .beer, millilitres: 355, abv: 10)
        #expect(abs(custom.standardDrinks - 2) < 0.05)
    }

    @Test func eveningDrinkCountFollowsTheLog() {
        var evening = EveningCheckIn(day: .now)
        evening.alcohol = [
            AlcoholEntry(kind: .beer, millilitres: 355, minutes: 20 * 60),
            AlcoholEntry(kind: .wine, millilitres: 148, minutes: 22 * 60 + 30),
            AlcoholEntry(kind: .spirits, millilitres: 44, minutes: 21 * 60),
        ]
        evening.syncDrinksFromAlcohol()
        #expect(evening.drinks == 3)
        #expect(evening.lastDrinkMinutes == 22 * 60 + 30)
    }

    @Test func aSmallDrinkStillCountsAsOne() {
        var evening = EveningCheckIn(day: .now)
        evening.alcohol = [AlcoholEntry(kind: .lightBeer, millilitres: 200)]
        evening.syncDrinksFromAlcohol()
        #expect(evening.drinks == 1)
    }

    @Test func clearingTheLogResetsTheCount() {
        var evening = EveningCheckIn(day: .now)
        evening.alcohol = [AlcoholEntry(kind: .beer, millilitres: 355)]
        evening.syncDrinksFromAlcohol()
        evening.alcohol = []
        evening.syncDrinksFromAlcohol()
        #expect(evening.drinks == 0)
        #expect(evening.alcohol == nil)
    }

    @Test func oldSavedCheckInsStillDecode() throws {
        let json = #"{"day": 0, "drinks": 2}"#
        let evening = try JSONDecoder().decode(EveningCheckIn.self, from: Data(json.utf8))
        #expect(evening.drinks == 2)
        #expect(evening.alcohol == nil)
    }
}

struct MaintenanceRobustnessTests {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    func day(_ offset: Int) -> Date { now.addingTimeInterval(Double(offset) * 86_400) }

    @Test func partlyLoggedDaysAreLeftOut() throws {
        // 20 full days at 2,400 and 8 days where only lunch (1,000) was logged; weight steady.
        let intake = (0..<28).map { DayValue(date: day(-28 + $0), value: $0 % 7 < 2 ? 1000 : 2400) }
        let weights = (0..<28).map { DayValue(date: day(-28 + $0), value: 80) }
        let result = try #require(AdaptiveTDEE.estimate(intake: intake, weights: weights, now: now))
        #expect(abs(result.maintenance - 2400) < 50)
        #expect(result.partialDaysSkipped == 8)
    }

    @Test func tooFewFullDaysGivesProgressInstead() {
        let intake = (0..<28).map { DayValue(date: day(-28 + $0), value: $0 < 10 ? 2400 : 900) }
        let weights = (0..<28).map { DayValue(date: day(-28 + $0), value: 80) }
        #expect(AdaptiveTDEE.estimate(intake: intake, weights: weights, now: now, expectedExpenditure: 2500) == nil)
        let progress = AdaptiveTDEE.progress(intake: intake, weights: weights, now: now, expectedExpenditure: 2500)
        #expect(progress.fullyLoggedDays == 10)
        #expect(progress.daysNeeded == 4)
    }

    @Test func creatineWaterIsNotCountedAsSurplus() throws {
        // Eating maintenance (2,500) while creatine adds ~1 kg of water over 4 weeks.
        let start = day(-28)
        let intake = (0..<28).map { DayValue(date: day(-28 + $0), value: 2500) }
        let weights = (0..<28).map { offset in
            DayValue(date: day(-28 + offset), value: 80 + AdaptiveTDEE.creatineWaterKg * Double(offset) / 28)
        }
        let naive = try #require(AdaptiveTDEE.estimate(intake: intake, weights: weights, now: now))
        let adjusted = try #require(AdaptiveTDEE.estimate(intake: intake, weights: weights, now: now, creatineStart: start))
        #expect(naive.maintenance < 2300)
        #expect(abs(adjusted.maintenance - 2500) < 60)
        #expect(adjusted.creatineWaterRemovedKg > 0.9)
    }

    @Test func longTimeCreatineUsersAreNotAdjusted() throws {
        let intake = (0..<28).map { DayValue(date: day(-28 + $0), value: 2500) }
        let weights = (0..<28).map { DayValue(date: day(-28 + $0), value: 80) }
        let result = try #require(AdaptiveTDEE.estimate(intake: intake, weights: weights, now: now, creatineStart: day(-200)))
        #expect(result.creatineWaterRemovedKg == 0)
        #expect(abs(result.maintenance - 2500) < 30)
    }
}
